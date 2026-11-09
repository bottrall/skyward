# frozen_string_literal: true

# Every constraint and index is named, so a violation names the same
# constraint on every database: SQLite reports an unnamed check by its
# expression, where PostgreSQL would make up these names.
module Skyward::ORM::Migrations::Script
  extend self

  ON_DELETE = {
    cascade: "CASCADE",
    restrict: "RESTRICT",
    set_null: "SET NULL",
    set_default: "SET DEFAULT",
    no_action: "NO ACTION"
  }.freeze #: Hash[Skyward::ORM::Tables::on_delete, String]

  # @rbs changes: Array[Skyward::ORM::Migrations::change]
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def write(changes, adapter)
    up = changes.map { |change| up(change, adapter) }.join("\n")
    down = changes.reverse.flat_map { |change| down(change) }.join
    "#{up}\n-- down\n#{down}"
  end

  private

  # @rbs change: Skyward::ORM::Migrations::change
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def up(change, adapter)
    case change
    when Skyward::ORM::Migrations::CreateTable then create(change, adapter)
    else add(change, adapter)
    end
  end

  # @rbs change: Skyward::ORM::Migrations::change
  # @rbs return: Array[String]
  def down(change)
    table = change.klass.table_name
    case change
    when Skyward::ORM::Migrations::CreateTable then ["DROP TABLE #{table};\n"]
    else change.columns.reverse.map { |column| "ALTER TABLE #{table} DROP COLUMN #{column.name};\n" }
    end
  end

  # Columns line up as a person would write them. A generated key's type runs
  # on into its identity clause, so it doesn't set the width.
  # @rbs change: Skyward::ORM::Migrations::CreateTable
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def create(change, adapter)
    klass = change.klass
    table = klass.table_name
    schema = klass.schema
    name_width = change.columns.map { |column| column.name.length }.max || 0
    identity = adapter.identity
    type_width = change.columns.reject { |column| identity && generated?(schema, column) }
                       .filter_map { |column| adapter.sql_type(column.type)&.length }.max || 0
    columns = change.columns.map do |column|
      found = definition(klass, column, adapter)
      next [false, todo_type(table, column)] unless found

      spec, clauses = found
      [true, "#{column.name.name.ljust(name_width)}  #{spec.ljust(type_width)} #{clauses}".rstrip]
    end #: Array[[bool, String]]
    uniques = schema.uniques.select { |columns| columns.size > 1 }.map do |unique|
      [true, "CONSTRAINT #{name(table, unique, "key")} UNIQUE (#{unique.join(", ")})"]
    end #: Array[[bool, String]]
    entries = [*columns, *uniques]
    last = entries.rindex { |definition, _| definition }
    lines = entries.each_with_index.map do |(definition, text), index|
      "  #{text}#{"," if definition && index != last}\n"
    end
    indexes = schema.indexes.map do |index|
      "CREATE INDEX #{name(table, index, "index")} ON #{table} (#{index.join(", ")});\n"
    end
    ["CREATE TABLE #{table} (\n", *lines, ");\n", *indexes].join
  end

  # @rbs change: Skyward::ORM::Migrations::AddColumns
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def add(change, adapter) = change.columns.map { |column| add_column(change.klass, column, adapter) }.join

  # The rows a table already has need a value for a new required column.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def add_column(klass, column, adapter)
    table = klass.table_name
    found = definition(klass, column, adapter)
    return "#{todo_type(table, column)}\n" unless found

    spec, clauses = found
    unless column.nullable || klass.schema.defaults.key?(column.name)
      todo = "-- TODO: #{table}.#{column.name} needs a DEFAULT for the rows #{table} already has\n"
    end
    "#{todo}ALTER TABLE #{table} ADD COLUMN #{"#{column.name} #{spec} #{clauses}".rstrip};\n"
  end

  # A column's type, and the clauses that follow it, or nil when it has no type.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: [String, String]?
  def definition(klass, column, adapter)
    sql_type = adapter.sql_type(column.type)
    return unless sql_type

    schema = klass.schema
    table = klass.table_name
    generated = generated?(schema, column)
    references = schema.references.select { |reference| reference.column == column.name }
    clauses = [
      ("NOT NULL" unless column.nullable || generated),
      (default(schema.defaults.fetch(column.name), adapter) if schema.defaults.key?(column.name)),
      ("CONSTRAINT #{table}_pkey PRIMARY KEY" if schema.primary_key == column.name),
      ("CONSTRAINT #{name(table, [column.name], "key")} UNIQUE" if schema.uniques.include?([column.name])),
      *checks(table, column, schema.checks),
      *references.map { |reference| reference(table, reference) }
    ].compact
    [[sql_type, (adapter.identity if generated)].compact.join(" "), clauses.join(" ")]
  end

  # @rbs schema: Skyward::ORM::Tables::Schema
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: bool
  def generated?(schema, column) = schema.primary_key == column.name && column.type == :integer

  # @rbs value: untyped
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def default(value, adapter)
    case value
    when Skyward::ORM::Tables::SQL then "DEFAULT #{adapter.default_expression(value.expression)}"
    else "DEFAULT #{literal(adapter.encode(value))}"
    end
  end

  # A symbol union's check comes first, as part of the column's type.
  # @rbs table: Symbol
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs checks: Array[Skyward::ORM::Tables::Check]
  # @rbs return: Array[String]
  def checks(table, column, checks)
    symbols = column.symbols.map { |symbol| literal(symbol.name) }.join(", ")
    rules = [
      *("#{column.name} IN (#{symbols})" if column.type == :enum),
      *checks.select { |check| check.column == column.name }.map { |check| rule(column.name, check.rule) }
    ]
    # PostgreSQL numbers a column's second check the same way.
    rules.each_with_index.map do |rule, index|
      "CONSTRAINT #{table}_#{column.name}_check#{index unless index.zero?} CHECK (#{rule})"
    end
  end

  # @rbs column: Symbol
  # @rbs rule: Skyward::ORM::Tables::SQL | Skyward::ORM::Tables::Length
  # @rbs return: String
  def rule(column, rule)
    case rule
    when Skyward::ORM::Tables::SQL then rule.expression
    else length(column, rule)
    end
  end

  # @rbs column: Symbol
  # @rbs length: Skyward::ORM::Tables::Length
  # @rbs return: String
  def length(column, length)
    min = length.min
    max = length.max
    if min && max then "length(#{column}) BETWEEN #{min} AND #{max}"
    elsif min then "length(#{column}) >= #{min}"
    else "length(#{column}) <= #{max}"
    end
  end

  # @rbs table: Symbol
  # @rbs reference: Skyward::ORM::Tables::Reference
  # @rbs return: String
  def reference(table, reference)
    on_delete = reference.on_delete
    "CONSTRAINT #{table}_#{reference.column}_fkey REFERENCES #{reference.table.table_name}" \
      "#{" ON DELETE #{ON_DELETE.fetch(on_delete)}" if on_delete}"
  end

  # @rbs table: Symbol
  # @rbs columns: Array[Symbol]
  # @rbs suffix: String
  # @rbs return: String
  def name(table, columns, suffix) = "#{table}_#{columns.join("_")}_#{suffix}"

  # @rbs table: Symbol
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: String
  def todo_type(table, column) = "-- TODO: #{table}.#{column.name} needs a type"

  # @rbs value: untyped
  # @rbs return: String
  def literal(value)
    case value
    when nil then "NULL"
    when String then "'#{value.gsub("'", "''")}'"
    when Integer, Float, true, false then value.to_s
    else literal(value.to_s)
    end
  end
end
