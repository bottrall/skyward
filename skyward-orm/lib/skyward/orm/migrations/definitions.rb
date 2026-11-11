# frozen_string_literal: true

# What a class's declarations make of its table, written as the catalog reads
# a table back, so a migration can write it and compare it with the database.
#
# Every constraint and index is named, so a violation names the same
# constraint on every database: SQLite reports an unnamed check by its
# expression, where PostgreSQL would make up these names.
module Skyward::ORM::Migrations::Definitions
  extend self

  ON_DELETE = {
    cascade: "CASCADE",
    restrict: "RESTRICT",
    set_null: "SET NULL",
    set_default: "SET DEFAULT",
    no_action: "NO ACTION"
  }.freeze #: Hash[Skyward::ORM::Tables::on_delete, String]

  # Each column's constraints, in the order a column lists them, then each
  # unique on more than one column.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Skyward::ORM::Tables::Column]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def constraints(klass, columns)
    schema = klass.schema
    table = klass.table_name
    on_columns = columns.flat_map do |column|
      name = column.name
      references = schema.references.select { |reference| reference.column == name }
      [
        (constraint("#{table}_pkey", :primary_key, [name], "PRIMARY KEY (#{name})") if schema.primary_key == name),
        (unique(table, [name]) if schema.uniques.include?([name])),
        *checks(table, column, schema.checks),
        *references.map { |reference| reference(table, reference) }
      ].compact
    end
    [*on_columns, *schema.uniques.reject(&:one?).map { |columns| unique(table, columns) }]
  end

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: Array[Skyward::ORM::Catalog::Index]
  def indexes(klass)
    table = klass.table_name
    klass.schema.indexes.map do |columns|
      name = name(table, columns, "index")
      Skyward::ORM::Catalog::Index.new(
        name:,
        columns:,
        unique: false,
        definition: "CREATE INDEX #{name} ON #{table} (#{columns.join(", ")})"
      )
    end
  end

  # The SQL that follows the column's DEFAULT, or nil when it has none.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String?
  def default(klass, column, adapter)
    defaults = klass.schema.defaults
    return unless defaults.key?(column.name)

    value = defaults.fetch(column.name)
    case value
    when Skyward::ORM::Tables::SQL then adapter.default_expression(value.expression)
    else literal(Skyward::ORM::Statements.encode(adapter, column, value))
    end
  end

  # The constraint as a column's own, in a column's definition.
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def inline(constraint)
    clause = case constraint.kind
             when :primary_key then "PRIMARY KEY"
             when :unique then "UNIQUE"
             when :check then constraint.definition
             else constraint.definition.delete_prefix("FOREIGN KEY (#{constraint.columns.fetch(0)}) ")
             end
    "CONSTRAINT #{constraint.name} #{clause}"
  end

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

  private

  # @rbs name: String
  # @rbs kind: Skyward::ORM::Catalog::constraint_kind
  # @rbs columns: Array[Symbol]
  # @rbs definition: String
  # @rbs references: Symbol?
  # @rbs return: Skyward::ORM::Catalog::Constraint
  def constraint(name, kind, columns, definition, references = nil)
    Skyward::ORM::Catalog::Constraint.new(name:, kind:, columns:, references:, definition:)
  end

  # @rbs table: Symbol
  # @rbs columns: Array[Symbol]
  # @rbs return: Skyward::ORM::Catalog::Constraint
  def unique(table, columns)
    constraint(name(table, columns, "key"), :unique, columns, "UNIQUE (#{columns.join(", ")})")
  end

  # A symbol union's check comes first, as part of the column's type.
  # @rbs table: Symbol
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs checks: Array[Skyward::ORM::Tables::Check]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def checks(table, column, checks)
    name = column.name
    symbols = column.symbols.map { |symbol| literal(symbol.name) }.join(", ")
    rules = [
      *("#{name} IN (#{symbols})" if column.type == :enum),
      *checks.select { |check| check.column == name }.map { |check| rule(name, check.rule) }
    ]
    # PostgreSQL numbers a column's second check the same way.
    rules.each_with_index.map do |rule, index|
      constraint("#{table}_#{name}_check#{index unless index.zero?}", :check, [name], "CHECK (#{rule})")
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
  # @rbs return: Skyward::ORM::Catalog::Constraint
  def reference(table, reference)
    column = reference.column
    on_delete = reference.on_delete
    parent = reference.table.table_name
    constraint(
      "#{table}_#{column}_fkey",
      :foreign_key,
      [column],
      "FOREIGN KEY (#{column}) REFERENCES #{parent}#{" ON DELETE #{ON_DELETE.fetch(on_delete)}" if on_delete}",
      parent
    )
  end

  # @rbs table: Symbol
  # @rbs columns: Array[Symbol]
  # @rbs suffix: String
  # @rbs return: String
  def name(table, columns, suffix) = "#{table}_#{columns.join("_")}_#{suffix}"
end
