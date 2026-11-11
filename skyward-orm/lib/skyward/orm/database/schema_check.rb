# frozen_string_literal: true

module Skyward::ORM::Database::SchemaCheck
  extend self

  # @rbs!
  #   type problem = [String, String, String]

  MIGRATE = "Run `skyward migrate`, or `skyward migration` if you haven't generated one." #: String

  # Only what the class declares is compared. Extra columns, indexes and
  # constraints are left to `skyward status`, which reports them.
  # @rbs (singleton(Skyward::ORM::Record) klass, Array[Skyward::ORM::Tables::Column] columns,
  #   Array[Skyward::ORM::Catalog::Table] tables, Skyward::ORM::_Adapter adapter) -> String?
  def mismatch(klass, columns, tables, adapter)
    name = klass.table_name
    table = tables.find { |candidate| candidate.name == name }
    problems = if table
                 columns.flat_map { |column| column_problems(klass, table, column, adapter) }
               else
                 [[name.to_s, "The database has no table #{name}.", MIGRATE]] #: Array[problem]
               end
    report(klass, name, problems) unless problems.empty?
  end

  private

  # @rbs (singleton(Skyward::ORM::Record) klass, Skyward::ORM::Catalog::Table table,
  #   Skyward::ORM::Tables::Column column, Skyward::ORM::_Adapter adapter) -> Array[problem]
  def column_problems(klass, table, column, adapter)
    name = column.name
    found = table.columns.find { |candidate| candidate.name == name }
    return [[name.to_s, "#{table.name} has no column #{name}.", MIGRATE]] unless found
    # An untyped column's values pass through as the driver returns them.
    return [] if column.type == :untyped

    stored = "#{table.name}.#{name}"
    declared = "#{klass}##{name}"
    type = "#{stored} is #{found.type}, but #{declared} needs #{adapter.sql_type(column.type)}."
    [
      (type unless adapter.compatible?(column.type, found.type)),
      (nullability(stored, declared, found.nullable) unless found.nullable == column.nullable)
    ].compact.map { |problem| [name.to_s, problem, "#{MIGRATE} Or change #{declared}'s type to match."] }
  end

  # @rbs stored: String
  # @rbs declared: String
  # @rbs nullable: bool
  # @rbs return: String
  def nullability(stored, declared, nullable)
    if nullable then "#{stored} allows NULL, but #{declared} doesn't."
    else "#{stored} is NOT NULL, but #{declared} allows nil."
    end
  end

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs table: Symbol
  # @rbs problems: Array[problem]
  # @rbs return: String
  def report(klass, table, problems)
    width = problems.map { |label, _, _| label.length }.max.to_i
    lines = problems.flat_map do |label, problem, fix|
      ["  #{label.ljust(width)}  #{problem}", "  #{" " * width}  #{fix}"]
    end
    ["#{klass} doesn't match the #{table} table", "", *lines].join("\n")
  end
end
