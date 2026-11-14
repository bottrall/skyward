# frozen_string_literal: true

module Skyward::ORM::Adapters::PostgreSQL
  extend self

  SQL_TYPES = {
    integer: 'bigint',
    float: 'double precision',
    decimal: 'numeric',
    string: 'text',
    bool: 'boolean',
    date: 'date',
    time: 'timestamptz',
    enum: 'text',
    uuid: 'uuid',
    int32: 'integer',
    int16: 'smallint',
    json: 'jsonb'
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, String]

  # As the catalog spells each type, which compatible? is given.
  COMPATIBLE = {
    integer: %w[bigint integer smallint],
    float: ['double precision', 'real'],
    decimal: ['numeric'],
    string: ['text', 'character varying', 'uuid', 'citext'],
    bool: ['boolean'],
    date: ['date'],
    time: ['timestamp with time zone', 'timestamp without time zone'],
    enum: ['text', 'character varying'],
    uuid: ['uuid'],
    int32: ['integer'],
    int16: ['smallint'],
    json: %w[jsonb json]
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, Array[String]]

  # COMPATIBLE read backwards, taking the narrowest type for each.
  COLUMN_TYPES = {
    'bigint' => :integer,
    'integer' => :int32,
    'smallint' => :int16,
    'double precision' => :float,
    'real' => :float,
    'numeric' => :decimal,
    'text' => :string,
    'character varying' => :string,
    'citext' => :string,
    'uuid' => :uuid,
    'boolean' => :bool,
    'date' => :date,
    'timestamp with time zone' => :time,
    'timestamp without time zone' => :time,
    'jsonb' => :json,
    'json' => :json
  }.freeze #: Hash[String, Skyward::ORM::Tables::column_type]

  # The catalog puts a length or precision in parentheses.
  MODIFIER = /\(\d+(?:,\d+)?\)/ #: Regexp

  # UTC, so a timestamp column, which has no zone, holds the same instant as a
  # timestamptz, and to the microsecond, as PostgreSQL keeps it. Its trailing
  # zeros go, as PostgreSQL writes a time back, so a default compares as text.
  TIME_FORMAT = '%Y-%m-%d %H:%M:%S.%6N' #: String
  TRAILING_ZEROS = /\.?0+\z/ #: Regexp

  # PostgreSQL reads a literal default back cast to its type, as 'normal'::text
  # or '{}'::text[], and quotes a number that isn't a plain integer or decimal,
  # as '-1'::integer.
  CAST = /\A(?<literal>'(?:[^']|'')*')::(?<type>[a-z ]+(?:\[\])?)\z/ #: Regexp
  NUMERIC = /\A(?:smallint|integer|bigint|numeric|real|double precision)\z/ #: Regexp

  # Float() refuses the special values PostgreSQL writes out.
  SPECIAL_FLOATS = {
    'Infinity' => Float::INFINITY,
    '-Infinity' => -Float::INFINITY,
    'NaN' => Float::NAN
  }.freeze #: Hash[String, Float]

  MIGRATION_LOCK = 7_310_420_115 #: Integer

  # Each value comes back as text, and a boolean as t or f.
  TRUE_TEXT = 't' #: String
  FALSE_TEXT = 'f' #: String

  VIOLATIONS = {
    '23505' => :unique,
    '23503' => :foreign_key,
    '23502' => :not_null,
    '23514' => :check
  }.freeze #: Hash[String, Skyward::ORM::violation_kind]

  CONSTRAINT_KINDS = {
    'p' => :primary_key,
    'u' => :unique,
    'f' => :foreign_key,
    'c' => :check
  }.freeze #: Hash[String, Skyward::ORM::Catalog::constraint_kind]

  # The tables an unqualified name finds, as every query names them.
  TABLES = "t.relkind IN ('r', 'p') AND t.relnamespace <> 'pg_catalog'::regnamespace " \
           'AND pg_table_is_visible(t.oid)' #: String

  # pg_attrdef holds a generated column's expression as if it were its default.
  COLUMNS = <<~SQL.freeze #: String
    SELECT t.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
      CASE WHEN a.attgenerated = '' THEN pg_get_expr(d.adbin, d.adrelid) END,
      CASE WHEN a.attgenerated <> '' THEN pg_get_expr(d.adbin, d.adrelid) END
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
  def driver = 'pg'

  # @rbs return: Symbol
  def adapter_name = :postgresql

  # Values are decoded from PostgreSQL's ISO text, whatever the server's
  # defaults, and times read and written in UTC. libpq prints each notice the
  # server sends, so only warnings and worse are sent, or `skyward migrate`
  # would print that schema_migrations already exists.
  # @rbs location: String
  # @rbs return: Skyward::ORM::_Connection
  def connect(location)
    require_close_prepared(PG::Connection)
    connection = PG.connect("postgresql://#{location}")
    connection.exec("SET TimeZone = 'UTC'; SET DateStyle = 'ISO'; SET client_min_messages = warning")
    Connection.new(connection, Skyward::ORM::Adapters::StatementCache.new)
  end

  # A connection closes each statement it evicts with close_prepared, which pg
  # compiles only against libpq 17 and later.
  # @rbs connection: Module
  # @rbs return: void
  def require_close_prepared(connection)
    return if connection.method_defined?(:close_prepared)

    raise Skyward::Core::BootError,
          'Skyward ORM needs the pg gem 1.6 or later, built against libpq 17 or later, for ' \
          "PG::Connection#close_prepared. Update the pg gem, or the libpq it's built against."
  end

  # @rbs (String _location, Integer size) -> Integer
  def pool_size(_location, size) = size

  # @rbs position: Integer
  # @rbs return: String
  def placeholder(position) = "$#{position}"

  # The protocol counts a statement's parameters in 16 bits.
  # @rbs return: Integer
  def bind_limit = 65_535

  # PostgreSQL takes an OFFSET with no LIMIT before it.
  # @rbs return: String?
  def unlimited = nil

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: String?
  def sql_type(column)
    element = column.element
    element ? "#{SQL_TYPES.fetch(element)}[]" : SQL_TYPES[column.type]
  end

  # @rbs return: String?
  def identity = 'GENERATED ALWAYS AS IDENTITY'

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
  # @rbs return: String?
  def end_migration = nil

  # @rbs expression: String
  # @rbs return: String
  def default_expression(expression) = expression

  # @rbs default: String
  # @rbs return: String
  def catalog_default(default)
    cast = CAST.match(default)
    return default unless cast

    literal = cast[:literal].to_s
    NUMERIC.match?(cast[:type].to_s) ? literal.delete("'") : literal
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs sql_type: String
  # @rbs return: bool
  def compatible?(column, sql_type)
    element = column.element
    return accepts?(column.type, sql_type) unless element

    sql_type.end_with?('[]') && accepts?(element, sql_type.delete_suffix('[]'))
  end

  # PostgreSQL compares numeric as it is.
  # @rbs (Skyward::ORM::Tables::column_type _type, String column) -> String
  def comparable(_type, column) = column

  # @rbs sql_type: String
  # @rbs return: Skyward::ORM::Tables::column_type?
  def column_type(sql_type) = COLUMN_TYPES[sql_type.sub(MODIFIER, '')]

  # The driver sends every other value as its to_s, which PostgreSQL reads.
  # @rbs value: untyped
  # @rbs return: untyped
  def encode(value)
    case value
    when Symbol then value.name
    # Without the exponent BigDecimal#to_s writes, as 0.15e1, so both adapters
    # bind the same text.
    # -0.0 is 0, but would be written "-0.0" and miss an = against 0 on SQLite.
    when BigDecimal then (value.zero? ? BigDecimal(0) : value).to_s('F')
    when Time then "#{value.getutc.strftime(TIME_FORMAT).sub(TRAILING_ZEROS, '')}+00"
    else value
    end
  end

  # The encoder quotes each item that needs it, the string NULL included. A
  # boolean is written as PostgreSQL writes one back, so a default reads back
  # as it was written.
  # @rbs items: Array[untyped]
  # @rbs return: String
  def encode_array(items)
    PG::TextEncoder::Array.new.encode(
      items.map do |item|
        case item
        when true then TRUE_TEXT
        when false then FALSE_TEXT
        else encode(item)
        end
      end
    )
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: String
  # @rbs return: String
  def decoding(column, value)
    element = column.element
    return scalar(column.type, value) unless element

    decoded = scalar(element, 'item')
    # Other SQL can write a NULL item, which the ORM never does; it stays nil rather than reading as false.
    "::PG::TextDecoder::Array.new.decode(#{value}).map { |item| item.nil? ? nil : (#{decoded}).freeze }.freeze"
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: untyped
  def decode(column, value) = Skyward::ORM::Adapters.decode(self, column, value)

  # @rbs (Skyward::ORM::_Connection connection) -> Array[Skyward::ORM::Catalog::Table]
  def tables(connection)
    index_rows = connection.execute(INDEXES).group_by(&:first)
    constraint_rows = connection.execute(CONSTRAINTS).group_by(&:first)
    connection.execute(COLUMNS).group_by(&:first).map do |name, rows|
      Skyward::ORM::Catalog::Table.new(
        name: name.to_sym,
        columns: rows.map do |_, column, type, not_null, default, generated|
          Skyward::ORM::Catalog::Column.new(
            name: column.to_sym,
            type:,
            nullable: not_null != TRUE_TEXT,
            default: default && catalog_default(default),
            generated:
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

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs sql_type: String
  # @rbs return: bool
  def accepts?(type, sql_type)
    accepted = COMPATIBLE[type]
    accepted.nil? || accepted.include?(sql_type.sub(MODIFIER, ''))
  end

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: String
  # @rbs return: String
  def scalar(type, value)
    case type
    when :integer, :int32, :int16 then "Integer(#{value}, 10)"
    when :float then "::Skyward::ORM::Adapters::PostgreSQL::SPECIAL_FLOATS.fetch(#{value}) { Float(#{value}) }"
    when :decimal then "BigDecimal(#{value})"
    when :bool then "#{value} == ::Skyward::ORM::Adapters::PostgreSQL::TRUE_TEXT"
    when :date then "::Date.iso8601(#{value})"
    # A timestamp column's text has no zone, so it's read as the UTC it was written in.
    when :time then "::Time.new(#{value}, in: \"UTC\").getutc"
    # An Array's item may be NULL, or an Array of its own, which names no Symbol.
    when :enum then "::String.try_convert(#{value})&.to_sym"
    when :json then "::JSON.parse(#{value}, freeze: true)"
    else "#{value}.freeze"
    end
  end

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
