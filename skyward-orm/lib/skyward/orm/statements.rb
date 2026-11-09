# frozen_string_literal: true

module Skyward::ORM::Statements
  extend self

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: [String, Array[untyped]]
  def insert(adapter, column_types, table, values)
    require_values(column_types, table, values)
    require_present(table, column_types.columns(table), values.keys)
    into = "INSERT INTO #{quote(table.table_name)}"
    returned = returning(table.schema.columns)
    return ["#{into} DEFAULT VALUES #{returned}", []] if values.empty?

    placeholders = Array.new(values.size) { |index| adapter.placeholder(index + 1) }
    [
      "#{into} (#{values.keys.map { |column| quote(column) }.join(", ")}) " \
      "VALUES (#{placeholders.join(", ")}) #{returned}",
      values.values.map { |value| adapter.encode(value) }
    ]
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Symbol]
  # @rbs return: void
  def require_columns(table, columns)
    known = table.schema.columns
    unknown = (columns - known).first #: Symbol?
    return unless unknown

    suggestion = DidYouMean::SpellChecker.new(dictionary: known).correct(unknown).first
    raise ArgumentError, "#{table} has no column #{unknown}.#{" Did you mean #{suggestion}?" if suggestion}"
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs conditions: Hash[Symbol, untyped]
  # @rbs return: void
  def require_conditions(column_types, table, conditions)
    refuse(column_types, table, conditions) do |column, value|
      Skyward::ORM::Tables::Values.mismatch(table, column, value)
    end
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: void
  def require_values(column_types, table, values)
    refuse(column_types, table, values) do |column, value|
      Skyward::ORM::Tables::Values.write_mismatch(table, column, value)
    end
  end

  # @rbs columns: Array[Symbol]
  # @rbs return: String
  def returning(columns) = "RETURNING #{columns.map { |column| quote(column) }.join(", ")}"

  # Quoted, so a column named order or user is still a column.
  # @rbs name: Symbol
  # @rbs return: String
  def quote(name) = %("#{name.name.gsub('"', '""')}")

  private

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs &: (Skyward::ORM::Tables::Column column, untyped value) -> String?
  # @rbs return: void
  def refuse(column_types, table, values)
    require_columns(table, values.keys)
    columns = column_types.columns(table).to_h { |column| [column.name, column] }
    refused = values.filter_map { |name, value| yield(columns.fetch(name), value) }.first
    raise ArgumentError, refused if refused
  end

  # An untyped column's nullability is unknown, so it's left to the database,
  # like a column the class doesn't declare.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Skyward::ORM::Tables::Column]
  # @rbs given: Array[Symbol]
  # @rbs return: void
  def require_present(table, columns, given)
    schema = table.schema
    required = columns.reject do |column|
      column.nullable || column.type == :untyped || column.name == schema.primary_key ||
        schema.defaults.key?(column.name)
    end
    missing = required.map(&:name) - given
    return if missing.empty?

    raise ArgumentError,
          "#{table}.insert needs #{missing.join(", ")}: a column that can't be NULL and has no default needs a value"
  end
end
