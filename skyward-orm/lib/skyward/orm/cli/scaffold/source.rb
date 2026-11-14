# frozen_string_literal: true

# A table class's file, written from its table as the catalog reads it. Each
# type, default and constraint is one the class's migration would write the
# same, so `skyward migration` changes only what a comment says it will.
module Skyward::ORM::CLI::Scaffold::Source
  extend self

  # Only a trailing s is dropped: ies becomes y, sses becomes ss, and ss stays.
  SINGULAR = /ies\z|sses\z|(?<!s)s\z/ #: Regexp
  SINGULARS = { 'ies' => 'y', 'sses' => 'ss' }.freeze #: Hash[String, String]

  QUOTED = /'((?:[^']|'')*)'/ #: Regexp
  LITERAL = /\A#{QUOTED}\z/ #: Regexp
  ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/ #: Regexp
  # A Time as SQLite's adapter decodes it, to the microsecond. PostgreSQL reads
  # a default back with a cast, so no Time is written back the same there.
  ISO_TIME = /\A(\d{4}-\d{2}-\d{2}) (?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?\z/ #: Regexp

  BOOLS = { 'true' => true, 'false' => false, '1' => true, '0' => false }.freeze #: Hash[String, bool]

  ENUM = Skyward::ORM::Tables::Column.new(
    name: :enum, type: :enum, nullable: false, symbols: [], element: nil
  ) #: Skyward::ORM::Tables::Column

  PARENTHESIZED = /\A\((.*)\)\z/m #: Regexp

  CHECK = /\ACHECK\s*\((.*)\)\z/im #: Regexp

  # What's left of a check that lists a column's values once its strings,
  # casts and punctuation are gone. SQLite keeps `priority IN ('low', 'high')`,
  # and PostgreSQL rewrites it as `priority = ANY (ARRAY['low'::text, 'high'::text])`.
  CAST = /::[a-z ]+(?:\[\])?/ #: Regexp
  PUNCTUATION = /[\s()\[\],"]/ #: Regexp
  LISTS = %w[IN =ANYARRAY].freeze #: Array[String]

  # A btree index on columns alone, as PostgreSQL writes one back, or as it was written on SQLite.
  PLAIN_INDEX = /\ACREATE\s+(?:UNIQUE\s+)?INDEX\s.*?\sON\s+[^\s(]+\s*(?:USING\s+btree\s+)?\(([^()]*)\)\z/im #: Regexp

  # The columns a foreign key names after the table it references, if it names any.
  REFERENCED = /\bREFERENCES\s+(?:"(?:[^"]|"")*"|[^\s(]+)\s*(?:\(([^)]*)\))?/i #: Regexp

  DROPPED = "  # `skyward migration` will drop these, since a table class can't declare them:\n" #: String
  REWRITTEN = '`skyward migration` will rewrite these defaults once, as the values below, since SQLite keeps each ' \
              'as it was written: ' #: String

  # @rbs (Skyward::ORM::Catalog::Table table, Array[Skyward::ORM::Catalog::Table] tables,
  #   Skyward::ORM::_Adapter adapter, Array[singleton(Skyward::ORM::Record)] classes) -> String
  def text(table, tables, adapter, classes)
    checks = table.constraints.select { |constraint| constraint.kind == :check }
    unions = table.columns.to_h { |column| [column.name, union(column, checks, adapter)] }.compact
    types = table.columns.to_h do |column|
      [column.name, unions.key?(column.name) ? :enum : adapter.column_type(column.type)]
    end #: Hash[Symbol, Skyward::ORM::Tables::column_type?]
    refined = types.values.intersect?(Skyward::ORM::Tables::ColumnTypes::REFINEMENTS.values)
    [
      "# rbs_inline: enabled\n",
      ("# @rbs use Skyward::ORM::*\n" if refined),
      "\nclass #{class_name(table.name)} < Skyward::ORM::Record\n",
      "  table #{literal(table.name)}\n",
      *declarations(table, tables, adapter, classes, checks - unions.values.map(&:first), types),
      "\n  # @dynamic #{table.columns.map(&:name).join(', ')}\n",
      *readers(table.columns, unions, types),
      "end\n"
    ].compact.join
  end

  # @rbs table: Symbol
  # @rbs return: String
  def class_name(table)
    table.name.split('_').map(&:capitalize).join.sub(SINGULAR) { |ending| SINGULARS.fetch(ending, '') }
  end

  # @rbs table: Skyward::ORM::Catalog::Table?
  # @rbs return: Array[Symbol]
  def primary_key(table) = table&.constraints&.find { |constraint| constraint.kind == :primary_key }&.columns || []

  private

  # Each line below `table`, in the README's order, with what the class can't
  # declare first, as a comment.
  # @rbs (Skyward::ORM::Catalog::Table table, Array[Skyward::ORM::Catalog::Table] tables,
  #   Skyward::ORM::_Adapter adapter, Array[singleton(Skyward::ORM::Record)] classes,
  #   Array[Skyward::ORM::Catalog::Constraint] checks, Hash[Symbol, Skyward::ORM::Tables::column_type?] types)
  #   -> Array[String]
  def declarations(table, tables, adapter, classes, checks, types)
    key = primary_key(table).fetch(0)
    references, unreferenced = table.constraints.select { |constraint| constraint.kind == :foreign_key }
                                    .partition { |constraint| reference?(constraint, tables) }
    column_checks, unchecked = checks.partition { |check| check.columns.one? }
    plain, unindexed = table.indexes.partition { |index| plain?(index) }
    unique_indexes, indexes = plain.partition(&:unique)
    defaults = table.columns.filter_map { |column| default(column, types[column.name], adapter) }
    declared, unread = defaults.partition { |_, value| value }
    rewritten = declared.reject(&:last).map { |column, _| column.name }
    undeclared = [*unread.map(&:first), *unreferenced, *unchecked, *unindexed].map do |undeclarable|
      comment(definition(undeclarable), '  #   ')
    end
    [
      (DROPPED unless undeclared.empty?),
      *undeclared,
      ("  primary_key #{literal(key)}\n" unless key == :id),
      *references.flat_map { |reference| reference(table.name, reference, classes) },
      (comment("#{REWRITTEN}#{rewritten.join(', ')}") unless rewritten.empty?),
      ("  default #{declared.map { |column, value| "#{column.name}: #{value}" }.join(', ')}\n" unless declared.empty?),
      *table.constraints.select { |constraint| constraint.kind == :unique }.map { |unique| columns('unique', unique) },
      *unique_indexes.flat_map do |index|
        [
          comment(
            "`skyward migration` will replace the unique index #{index.name} with a constraint on the same " \
            'columns.'
          ),
          columns('unique', index)
        ]
      end,
      *column_checks.map do |check|
        "  check #{literal(check.columns.fetch(0))}, Skyward.sql(#{literal(rule(check))})\n"
      end,
      *indexes.map { |index| columns('index', index) }
    ].compact
  end

  # @rbs columns: Array[Skyward::ORM::Catalog::Column]
  # @rbs unions: Hash[Symbol, [Skyward::ORM::Catalog::Constraint, Array[Symbol]]]
  # @rbs types: Hash[Symbol, Skyward::ORM::Tables::column_type?]
  # @rbs return: Array[String]
  def readers(columns, unions, types)
    width = columns.map { |column| column.name.length }.max.to_i
    columns.flat_map do |column|
      name = column.name
      column_type = types[name]
      symbols = unions[name]&.last
      type = if symbols then symbols.map(&:inspect).join(' | ')
             elsif column_type then Skyward::ORM::Tables::Values::WRITTEN.fetch(column_type)
             else 'untyped'
             end
      rbs = if column_type.nil? || !column.nullable then type
            elsif symbols then "(#{type})?"
            else "#{type}?"
            end
      untyped = if column.type.empty? then "#{name} has no SQL type, so it's untyped."
                else "#{name} is #{column.type}, which has no column type, so it's untyped."
                end
      [
        (comment(untyped) unless column_type),
        "  attr_reader :#{name.name.ljust(width)}  #: #{rbs}\n"
      ].compact
    end
  end

  # A text column whose check lists only strings is a symbol union, and its
  # type makes that check.
  # @rbs (Skyward::ORM::Catalog::Column column, Array[Skyward::ORM::Catalog::Constraint] checks,
  #   Skyward::ORM::_Adapter adapter) -> [Skyward::ORM::Catalog::Constraint, Array[Symbol]]?
  def union(column, checks, adapter)
    return unless adapter.column_type(column.type) == :string && adapter.compatible?(ENUM, column.type)

    found = checks.find do |check|
      rule = rule(check)
      residue = rule.gsub(QUOTED, '').gsub(CAST, '').gsub(PUNCTUATION, '').upcase
      check.columns == [column.name] && rule.match?(QUOTED) &&
        LISTS.any? { |list| residue == "#{column.name.upcase}#{list}" }
    end
    return unless found

    symbols = rule(found).scan(QUOTED).map { |(value)| value.to_s.gsub("''", "'").to_sym }
    [found, symbols]
  end

  # A literal the column's type reads is that value, if it's written back the
  # same. Anything else is SQL, without the parentheses SQLite's adapter puts
  # back, since its default_expression adds them again. The bool says whether
  # it's written back the same. SQLite keeps a literal as it was written, even
  # in parentheses, so one no value writes back the same, such as 1.50, is the
  # value it reads as, which a migration rewrites it as once, or nil when it
  # reads as none.
  # @rbs (Skyward::ORM::Catalog::Column column, Skyward::ORM::Tables::column_type? type,
  #   Skyward::ORM::_Adapter adapter) -> [Skyward::ORM::Catalog::Column, String?, bool]?
  def default(column, type, adapter)
    sql = column.default
    return if sql.nil? || sql == Skyward::ORM::Migrations::Diff::NULL

    read = values(sql, type)
    literal = read.filter_map do |value|
      ruby(value) if Skyward::ORM::Migrations::Definitions.literal(adapter.encode(value)) == sql
    end.first
    return [column, literal, true] if literal

    expression = [sql, sql[PARENTHESIZED, 1]].compact.find { |candidate| adapter.default_expression(candidate) == sql }
    return [column, "Skyward.sql(#{literal(expression)})", true] if expression

    [column, (ruby(read.first) unless read.empty?), false]
  end

  # @rbs sql: String
  # @rbs type: Skyward::ORM::Tables::column_type?
  # @rbs return: Array[untyped]
  def values(sql, type)
    string = sql[LITERAL, 1]&.gsub("''", "'")
    # SQLite reads 010 as 10, where Ruby's Integer would read it as octal.
    integer = Integer(sql, 10, exception: false)
    float = Float(sql, exception: false)
    case type
    when :integer, :int32, :int16 then [integer]
    when :float then [integer, float]
    when :bool then [BOOLS[sql.downcase]]
    when :string, :uuid then [string]
    when :enum then [string&.to_sym]
    when :date then [date(string)]
    when :time then [time(string)]
    when nil then [integer, float, string]
    else [] #: Array[untyped]
    end.compact
  end

  # @rbs string: String?
  # @rbs return: Date?
  def date(string)
    match = string&.match(ISO_DATE)
    return unless match

    year, month, day = match.captures.map(&:to_i) #: [Integer, Integer, Integer]
    Date.new(year, month, day) if Date.valid_date?(year, month, day)
  end

  # @rbs string: String?
  # @rbs return: Time?
  def time(string)
    Time.new(string, in: 'UTC') if string && date(string[ISO_TIME, 1])
  end

  # @rbs value: untyped
  # @rbs return: String
  def ruby(value)
    case value
    when Date then "Date.new(#{value.year}, #{value.month}, #{value.day})"
    when Time
      parts = [value.year, value.month, value.day, value.hour, value.min, value.sec,
               (value.usec unless value.usec.zero?)]
      "Time.utc(#{parts.compact.join(', ')})"
    else literal(value)
    end
  end

  # Ruby source for a value in the shared style: a String or a quoted Symbol in
  # single quotes, unless it holds a quote, a backslash or a character only an
  # escape can write, which double quotes are for.
  # @rbs value: untyped
  # @rbs return: String
  def literal(value)
    case value
    when String then single_quotable?(value) ? "'#{value}'" : value.inspect
    when Symbol
      written = value.inspect
      written.start_with?(':"') && single_quotable?(value.name) ? ":'#{value.name}'" : written
    else value.inspect
    end
  end

  # @rbs text: String
  # @rbs return: bool
  def single_quotable?(text) = !text.match?(/['\\]/) && text.match?(/\A[[:print:]]*\z/)

  # A foreign key a class declares is on one column, and refers to the
  # primary key of the table it references.
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs return: bool
  def reference?(constraint, tables)
    key = primary_key(tables.find { |table| table.name == constraint.references })
    listed = constraint.definition[REFERENCED, 1]&.split(',')&.map { |column| column.strip.delete('"').to_sym }
    constraint.columns.one? && key.one? && (listed.nil? || listed == key)
  end

  # @rbs table: Symbol
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: Array[String]
  def reference(table, constraint, classes)
    # reference? found the table it references.
    referenced = constraint.references #: Symbol
    owner = classes.find { |klass| klass.table_name == referenced }
    action = constraint.definition[Skyward::ORM::Migrations::Diff::ON_DELETE, 1].to_s.downcase.split.join('_')
    on_delete = ", on_delete: :#{action}" unless ['', 'no_action'].include?(action)
    line = "  references #{literal(constraint.columns.fetch(0))}, #{owner || class_name(referenced)}#{on_delete}\n"
    return [line] if owner || referenced == table

    [comment("#{referenced} has no class yet. Scaffold it too: skyward scaffold #{referenced}"), line]
  end

  # @rbs index: Skyward::ORM::Catalog::Index
  # @rbs return: bool
  def plain?(index)
    keys = index.definition[PLAIN_INDEX, 1]
    !keys.nil? && keys.split(',').map { |key| key.strip.delete('"') } == index.columns.map(&:name)
  end

  # @rbs check: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def rule(check) = check.definition[CHECK, 1].to_s

  # @rbs declaration: String
  # @rbs key: Skyward::ORM::Catalog::Constraint | Skyward::ORM::Catalog::Index
  # @rbs return: String
  def columns(declaration, key) = "  #{declaration} #{key.columns.map { |column| literal(column) }.join(', ')}\n"

  # Every line of the text is commented, since a definition or name the
  # database keeps can hold a newline.
  # @rbs text: String
  # @rbs prefix: String
  # @rbs return: String
  def comment(text, prefix = '  # ') = "#{text.gsub(/^/, prefix)}\n"

  # @rbs undeclarable: Skyward::ORM::Catalog::Column | Skyward::ORM::Catalog::Constraint | Skyward::ORM::Catalog::Index
  # @rbs return: String
  def definition(undeclarable)
    case undeclarable
    when Skyward::ORM::Catalog::Column then "#{undeclarable.name} DEFAULT #{undeclarable.default}"
    when Skyward::ORM::Catalog::Index then undeclarable.definition
    else [("CONSTRAINT #{undeclarable.name}" if undeclarable.name), undeclarable.definition].compact.join(' ')
    end
  end
end
