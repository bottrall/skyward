# frozen_string_literal: true

module Skyward::ORM::Adapters::PostgreSQL
  extend self

  SQL_TYPES = {
    integer: "bigint",
    float: "double precision",
    string: "text",
    bool: "boolean",
    date: "date",
    time: "timestamptz",
    enum: "text"
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, String]

  # As the catalog spells each type, which compatible? is given.
  COMPATIBLE = {
    integer: %w[bigint integer smallint],
    float: ["double precision"],
    string: ["text", "character varying"],
    bool: ["boolean"],
    date: ["date"],
    time: ["timestamp with time zone", "timestamp without time zone"],
    enum: ["text", "character varying"]
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, Array[String]]

  # The catalog puts a length or precision in parentheses.
  MODIFIER = /\(\d+(?:,\d+)?\)/ #: Regexp

  # UTC, so a timestamp column, which has no zone, holds the same instant as a
  # timestamptz, and to the microsecond, as PostgreSQL keeps it. Its trailing
  # zeros go, as PostgreSQL writes a time back, so a default compares as text.
  TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%6N" #: String
  TRAILING_ZEROS = /\.?0+\z/ #: Regexp

  # PostgreSQL reads a literal default back cast to its type, as 'normal'::text,
  # and quotes a number that isn't a plain integer or decimal, as '-1'::integer.
  CAST = /\A(?<literal>'(?:[^']|'')*')::(?<type>[a-z ]+)\z/ #: Regexp
  NUMERIC = /\A(?:smallint|integer|bigint|numeric|real|double precision)\z/ #: Regexp

  # Float() refuses the special values PostgreSQL writes out.
  SPECIAL_FLOATS = {
    "Infinity" => Float::INFINITY,
    "-Infinity" => -Float::INFINITY,
    "NaN" => Float::NAN
  }.freeze #: Hash[String, Float]

  MIGRATION_LOCK = 7_310_420_115 #: Integer

  # Each value comes back as text, and a boolean as t or f.
  TRUE_TEXT = "t" #: String

  VIOLATIONS = {
    "23505" => :unique,
    "23503" => :foreign_key,
    "23502" => :not_null,
    "23514" => :check
  }.freeze #: Hash[String, Skyward::ORM::violation_kind]

  CONSTRAINT_KINDS = {
    "p" => :primary_key,
    "u" => :unique,
    "f" => :foreign_key,
    "c" => :check
  }.freeze #: Hash[String, Skyward::ORM::Catalog::constraint_kind]

  # The tables an unqualified name finds, as every query names them.
  TABLES = "t.relkind IN ('r', 'p') AND t.relnamespace <> 'pg_catalog'::regnamespace " \
           "AND pg_table_is_visible(t.oid)" #: String

  COLUMNS = <<~SQL.freeze #: String
    SELECT t.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
    FROM pg_catalog.pg_class AS t
    JOIN pg_catalog.pg_attribute AS a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_catalog.pg_attrdef AS d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE #{TABLES}
    ORDER BY t.relname, a.attnum
  SQL

  # Leaves out the indexes primary keys and unique constraints make, as SQLite's does.
  INDEXES = <<~SQL.freeze #: String
    SELECT t.relname, i.relname, x.indisunique, a.attname, pg_get_indexdef(x.indexrelid)
    FROM pg_catalog.pg_index AS x
    JOIN pg_catalog.pg_class AS t ON t.oid = x.indrelid
    JOIN pg_catalog.pg_class AS i ON i.oid = x.indexrelid
    CROSS JOIN LATERAL unnest(x.indkey::int2[]) WITH ORDINALITY AS k(attnum, position)
    LEFT JOIN pg_catalog.pg_attribute AS a ON a.attrelid = t.oid AND a.attnum = k.attnum
    WHERE #{TABLES} AND k.position <= x.indnkeyatts AND NOT EXISTS (
      SELECT FROM pg_catalog.pg_constraint AS c WHERE c.conindid = x.indexrelid AND c.contype IN ('p', 'u')
    )
    ORDER BY t.relname, i.relname, k.position
  SQL

  # A check on no column has no conkey, so the join keeps it with no columns.
  CONSTRAINTS = <<~SQL.freeze #: String
    SELECT t.relname, c.conname, c.contype, a.attname, r.relname, pg_get_constraintdef(c.oid)
    FROM pg_catalog.pg_constraint AS c
    JOIN pg_catalog.pg_class AS t ON t.oid = c.conrelid
    LEFT JOIN pg_catalog.pg_class AS r ON r.oid = c.confrelid
    LEFT JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, position) ON true
    LEFT JOIN pg_catalog.pg_attribute AS a ON a.attrelid = t.oid AND a.attnum = k.attnum
    WHERE #{TABLES} AND c.contype IN ('p', 'u', 'f', 'c')
    ORDER BY t.relname, c.conname, k.position
  SQL

  # @rbs return: String
  def driver = "pg"

  # Values are decoded from PostgreSQL's ISO text, whatever the server's
  # defaults, and times read and written in UTC. libpq prints each notice the
  # server sends, so only warnings and worse are sent, or `skyward migrate`
  # would print that schema_migrations already exists.
  # @rbs location: String
  # @rbs return: Skyward::ORM::_Connection
  def connect(location)
    connection = PG.connect("postgresql://#{location}")
    connection.exec("SET TimeZone = 'UTC'; SET DateStyle = 'ISO'; SET client_min_messages = warning")
    Connection.new(connection)
  end

  # @rbs (String _location, Integer size) -> Integer
  def pool_size(_location, size) = size

  # @rbs position: Integer
  # @rbs return: String
  def placeholder(position) = "$#{position}"

  # PostgreSQL takes an OFFSET with no LIMIT before it.
  # @rbs return: String?
  def unlimited = nil

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs return: String?
  def sql_type(type) = SQL_TYPES[type]

  # @rbs return: String?
  def identity = "GENERATED ALWAYS AS IDENTITY"

  # @rbs return: bool
  def alters_in_place? = true

  # A second migrator waits at the lock until the first commits, and then sees
  # what it ran. Any fixed key will do: the lock is the database's own.
  # @rbs return: String
  def begin_migration = "BEGIN; SELECT pg_advisory_xact_lock(#{MIGRATION_LOCK})"

  # PostgreSQL checks each foreign key as the migration writes.
  # @rbs (Skyward::ORM::_Connection _connection) -> Array[String]
  def foreign_key_violations(_connection) = []

  # Ending the transaction released the lock, and nothing else was set.
  # @rbs return: String
  def end_migration = ""

  # @rbs expression: String
  # @rbs return: String
  def default_expression(expression) = expression

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs sql_type: String
  # @rbs return: bool
  def compatible?(type, sql_type)
    accepted = COMPATIBLE[type]
    accepted.nil? || accepted.include?(sql_type.sub(MODIFIER, ""))
  end

  # The driver sends every other value as its to_s, which PostgreSQL reads.
  # @rbs value: untyped
  # @rbs return: untyped
  def encode(value)
    case value
    when Symbol then value.name
    when Time then "#{value.getutc.strftime(TIME_FORMAT).sub(TRAILING_ZEROS, "")}+00"
    else value
    end
  end

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: untyped
  # @rbs return: untyped
  def decode(type, value)
    case type
    when :integer then Integer(value, 10)
    when :float then SPECIAL_FLOATS.fetch(value) { Float(value) }
    when :bool then value == TRUE_TEXT
    when :date then Date.iso8601(value)
    # A timestamp column's text has no zone, so it's read as the UTC it was written in.
    when :time then Time.new(value, in: "UTC").getutc
    when :enum then value.to_sym
    else value.freeze
    end
  end

  # @rbs (Skyward::ORM::_Connection connection) -> Array[Skyward::ORM::Catalog::Table]
  def tables(connection)
    index_rows = connection.execute(INDEXES).group_by(&:first)
    constraint_rows = connection.execute(CONSTRAINTS).group_by(&:first)
    connection.execute(COLUMNS).group_by(&:first).map do |name, rows|
      Skyward::ORM::Catalog::Table.new(
        name: name.to_sym,
        columns: rows.map do |_, column, type, not_null, default|
          Skyward::ORM::Catalog::Column.new(
            name: column.to_sym, type:, nullable: not_null != TRUE_TEXT, default: default(default)
          )
        end,
        indexes: indexes(index_rows.fetch(name, [])),
        constraints: constraints(constraint_rows.fetch(name, []))
      )
    end
  end

  # @rbs (StandardError error, Array[Skyward::ORM::Catalog::Table] tables, Symbol? _table)
  #   -> Skyward::ORM::Violation?
  def violation(error, tables, _table)
    result = error.result if error.is_a?(PG::Error)
    kind = VIOLATIONS[result&.error_field(PG::PG_DIAG_SQLSTATE).to_s]
    return unless result && kind

    constraint = result.error_field(PG::PG_DIAG_CONSTRAINT_NAME)
    Skyward::ORM::Violation.new(
      kind:,
      constraint:,
      columns: if kind == :not_null
                 [result.error_field(PG::PG_DIAG_COLUMN_NAME)].compact.map(&:to_sym)
               else
                 constrained(tables, result.error_field(PG::PG_DIAG_TABLE_NAME), constraint)
               end,
      message: result.error_field(PG::PG_DIAG_MESSAGE_PRIMARY).to_s
    )
  end

  private

  # @rbs rows: Array[Array[untyped]]
  # @rbs return: Array[Skyward::ORM::Catalog::Index]
  def indexes(rows)
    rows.group_by { |row| row.fetch(1) }.map do |name, keys|
      Skyward::ORM::Catalog::Index.new(
        name:,
        # An index on an expression has no column there.
        columns: keys.filter_map { |row| row.fetch(3)&.to_sym },
        unique: keys.fetch(0).fetch(2) == TRUE_TEXT,
        definition: keys.fetch(0).fetch(4)
      )
    end
  end

  # @rbs rows: Array[Array[untyped]]
  # @rbs return: Array[Skyward::ORM::Catalog::Constraint]
  def constraints(rows)
    rows.group_by { |row| row.fetch(1) }.map do |name, keys|
      first = keys.fetch(0)
      Skyward::ORM::Catalog::Constraint.new(
        name:,
        kind: CONSTRAINT_KINDS.fetch(first.fetch(2)),
        columns: keys.filter_map { |row| row.fetch(3)&.to_sym },
        references: first.fetch(4)&.to_sym,
        definition: first.fetch(5)
      )
    end
  end

  # @rbs expression: String?
  # @rbs return: String?
  def default(expression)
    cast = CAST.match(expression.to_s)
    return expression unless cast

    literal = cast[:literal].to_s
    NUMERIC.match?(cast[:type].to_s) ? literal.delete("'") : literal
  end

  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: String?
  # @rbs name: String?
  # @rbs return: Array[Symbol]
  def constrained(tables, table, name)
    found = tables.find { |candidate| candidate.name.name == table }
    return [] unless found

    [*found.constraints, *found.indexes].find { |key| key.name == name }&.columns || []
  end
end
