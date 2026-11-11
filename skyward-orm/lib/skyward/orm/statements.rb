# frozen_string_literal: true

module Skyward::ORM::Statements
  extend self

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: [String, Array[untyped]]
  def insert(adapter, column_types, tables, table, values)
    require_values(column_types, tables, table, values)
    require_present(table, column_types.columns(table), values.keys, generated(tables, table), "#{table}.insert")
    return ["INSERT INTO #{quote(table.table_name)} DEFAULT VALUES", []] if values.empty?

    inserting(adapter, column_types, table, values.keys, [values])
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: [String, Array[untyped]]
  def insert_all(adapter, column_types, tables, table, rows)
    columns = rows.fetch(0).keys
    # Neither database takes DEFAULT VALUES for more than one row.
    if columns.empty?
      raise ArgumentError, "#{table}.insert_all row 0 has no columns. Use #{table}.insert for a row of defaults."
    end

    require_bindable(adapter, table, rows.size, columns.size)
    generated = generated(tables, table)
    rows.each_with_index do |row, index|
      subject = "#{table}.insert_all row #{index}"
      require_alike(subject, columns, row.keys)
      refused = unwritable(column_types, generated, table, row)
      raise ArgumentError, "#{subject}: #{refused}" if refused
    end
    # Every row has row 0's columns by now, so only row 0 can lack one.
    require_present(table, column_types.columns(table), columns, generated, "#{table}.insert_all row 0")
    inserting(adapter, column_types, table, columns, rows)
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: Array[untyped]
  def binds(adapter, column_types, table, values)
    columns = by_name(column_types, table)
    values.map { |name, value| encode(adapter, columns.fetch(name), value) }
  end

  # Only a column says a Hash is JSON: bound to a ? in SQL, it's refused,
  # since the driver would spread it across placeholders.
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: untyped
  def encode(adapter, column, value)
    column.type == :json && !value.nil? ? JSON.generate(value) : adapter.encode(value)
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Symbol]
  # @rbs return: void
  def require_columns(table, columns)
    refused = unknown(table, columns)
    raise ArgumentError, refused if refused
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs conditions: Hash[Symbol, untyped]
  # @rbs return: void
  def require_conditions(column_types, table, conditions)
    refused = refusal(column_types, table, conditions) do |column, value|
      Skyward::ORM::Tables::Values.mismatch(table, column, value)
    end
    raise ArgumentError, refused if refused
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: void
  def require_values(column_types, tables, table, values)
    refused = unwritable(column_types, generated(tables, table), table, values)
    raise ArgumentError, refused if refused
  end

  # @rbs columns: Array[Symbol]
  # @rbs return: String
  def returning(columns) = "RETURNING #{columns.map { |column| quote(column) }.join(", ")}"

  # Quoted, so a column named order or user is still a column.
  # @rbs name: Symbol
  # @rbs return: String
  def quote(name) = %("#{name.name.gsub('"', '""')}")

  private

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Symbol]
  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: [String, Array[untyped]]
  def inserting(adapter, column_types, table, columns, rows)
    tuples = Array.new(rows.size * columns.size) { |index| adapter.placeholder(index + 1) }
                  .each_slice(columns.size).map { |placeholders| "(#{placeholders.join(", ")})" }
    named = by_name(column_types, table)
    [
      "INSERT INTO #{quote(table.table_name)} (#{columns.map { |column| quote(column) }.join(", ")}) " \
      "VALUES #{tuples.join(", ")}",
      rows.flat_map { |row| columns.map { |column| encode(adapter, named.fetch(column), row.fetch(column)) } }
    ]
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Symbol]
  # @rbs return: String?
  def unknown(table, columns)
    known = table.schema.columns
    name = (columns - known).first #: Symbol?
    return unless name

    suggestion = DidYouMean::SpellChecker.new(dictionary: known).correct(name).first
    "#{table} has no column #{name}.#{" Did you mean #{suggestion}?" if suggestion}"
  end

  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs return: Array[Symbol]
  def generated(tables, table)
    found = tables.find { |candidate| candidate.name == table.table_name }
    found ? found.columns.select(&:generated).map(&:name) : []
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs generated: Array[Symbol]
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: String?
  def unwritable(column_types, generated, table, values)
    written = (values.keys & generated).first
    return "#{table}.#{written} is generated by the database, so it can't be written" if written

    refusal(column_types, table, values) do |column, value|
      Skyward::ORM::Tables::Values.write_mismatch(table, column, value)
    end
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs values: Hash[Symbol, untyped]
  # @rbs &: (Skyward::ORM::Tables::Column column, untyped value) -> String?
  # @rbs return: String?
  def refusal(column_types, table, values)
    refused = unknown(table, values.keys)
    return refused if refused

    columns = by_name(column_types, table)
    values.filter_map { |name, value| yield(columns.fetch(name), value) }.first
  end

  # An untyped column's nullability is unknown, so it's left to the database,
  # like a column the class doesn't declare.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Skyward::ORM::Tables::Column]
  # @rbs given: Array[Symbol]
  # @rbs generated: Array[Symbol]
  # @rbs subject: String
  # @rbs return: void
  def require_present(table, columns, given, generated, subject)
    schema = table.schema
    required = columns.reject do |column|
      column.nullable || column.type == :untyped || column.name == schema.primary_key ||
        schema.defaults.key?(column.name) || generated.include?(column.name)
    end
    missing = required.map(&:name) - given
    return if missing.empty?

    raise ArgumentError,
          "#{subject} needs #{missing.join(", ")}: a column that can't be NULL and has no default needs a value"
  end

  # Matched as sets, since each row's values are read in the first row's order.
  # @rbs subject: String
  # @rbs columns: Array[Symbol]
  # @rbs given: Array[Symbol]
  # @rbs return: void
  def require_alike(subject, columns, given)
    differences = { "has" => given - columns, "lacks" => columns - given }.reject { |_, names| names.empty? }
    return if differences.empty?

    raise ArgumentError,
          "#{subject} #{differences.map { |verb, names| "#{verb} #{names.join(", ")}" }.join(" and ")}, " \
          "unlike row 0: every row needs the same columns"
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs rows: Integer
  # @rbs columns: Integer
  # @rbs return: void
  def require_bindable(adapter, table, rows, columns)
    limit = adapter.bind_limit
    binds = rows * columns
    return if binds <= limit

    raise ArgumentError,
          "#{table}.insert_all binds #{binds} values, #{columns} for each of #{rows} rows, but the " \
          "database binds at most #{limit} in one statement. Split the rows, in a Skyward.transaction if they " \
          "must land together."
  end

  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs return: Hash[Symbol, Skyward::ORM::Tables::Column]
  def by_name(column_types, table) = column_types.columns(table).to_h { |column| [column.name, column] }
end
