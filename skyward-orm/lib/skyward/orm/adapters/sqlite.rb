# frozen_string_literal: true

module Skyward::ORM::Adapters::SQLite
  extend self

  # The first SQLite with RETURNING, which every write into a row class uses.
  MINIMUM_VERSION = Gem::Version.new('3.35') #: Gem::Version

  SQL_TYPES = {
    integer: 'INTEGER',
    float: 'REAL',
    decimal: 'TEXT',
    string: 'TEXT',
    bool: 'INTEGER',
    date: 'TEXT',
    time: 'TEXT',
    enum: 'TEXT',
    uuid: 'TEXT',
    int32: 'INTEGER',
    int16: 'INTEGER',
    json: 'TEXT',
    array: 'TEXT'
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, String]

  # Fixed width and UTC, so text order is time order, and to the microsecond,
  # as PostgreSQL keeps it. It's the format of SQLite's own CURRENT_TIMESTAMP,
  # with the fraction added, so the two compare.
  TIME_FORMAT = '%Y-%m-%d %H:%M:%S.%6N' #: String

  # SQLite's extended result codes: SQLITE_CONSTRAINT_CHECK, _FOREIGNKEY,
  # _NOTNULL, _PRIMARYKEY and _UNIQUE.
  VIOLATIONS = {
    275 => :check,
    787 => :foreign_key,
    1299 => :not_null,
    1555 => :unique,
    2067 => :unique
  }.freeze #: Hash[Integer, Skyward::ORM::violation_kind]

  # SQLite enforces a RESTRICT foreign key as a trigger would, so it reports
  # SQLITE_CONSTRAINT_TRIGGER, and only the message tells it from a trigger's RAISE.
  TRIGGER = 1811 #: Integer
  RESTRICTED = 'FOREIGN KEY constraint failed' #: String

  # Types whose values keep their meaning under NUMERIC affinity, which Rails
  # gives BOOLEAN, DATE and DATETIME. A boolean is already a number, and a date
  # or time is never a well-formed number, so none is converted. A String or a
  # BigDecimal would be: NUMERIC turns "1.10" into 1.1.
  NUMERIC_SAFE = %i[bool date time].freeze #: Array[Skyward::ORM::Tables::column_type]

  # The names Rails writes for the NUMERIC_SAFE types, with any precision, as
  # in DATETIME(6). Nothing else in the catalog tells a bool, Date or Time from
  # an Integer or String, since a migration stores them as INTEGER and TEXT.
  NUMERIC_NAMES = {
    'BOOLEAN' => :bool,
    'DATE' => :date,
    'DATETIME' => :time
  }.freeze #: Hash[String, Skyward::ORM::Tables::column_type]
  PRECISION = /\s*\(.*\)\z/ #: Regexp

  AFFINITY_TYPES = {
    integer: :integer,
    real: :float,
    text: :string
  }.freeze #: Hash[Symbol, Skyward::ORM::Tables::column_type]

  UNIQUE_KINDS = %i[unique primary_key].freeze #: Array[Skyward::ORM::Catalog::constraint_kind]

  BUSY_TIMEOUT_MS = 5000 #: Integer

  # table_info leaves out generated columns, which table_xinfo marks hidden 2
  # (virtual) or 3 (stored). Hidden 1 is a virtual table's own hidden column.
  COLUMNS = <<~SQL #: String
    SELECT m.name, m.sql, c.name, c.type, c."notnull", c.pk, c.dflt_value
    FROM sqlite_schema AS m JOIN pragma_table_xinfo(m.name) AS c
    WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite\\_%' ESCAPE '\\' AND c.hidden <> 1
    ORDER BY m.name, c.cid
  SQL

  INDEXES = <<~SQL #: String
    SELECT m.name, i.name, i."unique", c.name, s.sql
    FROM sqlite_schema AS m JOIN pragma_index_list(m.name) AS i JOIN pragma_index_info(i.name) AS c
      JOIN sqlite_schema AS s ON s.type = 'index' AND s.name = i.name
    WHERE m.type = 'table' AND i.origin = 'c'
    ORDER BY m.name, i.name, c.seqno
  SQL

  # What SQLite takes as a default without parentheses: a string, blob or
  # number, NULL, TRUE or FALSE.
  LITERAL = /\A(?:'(?:[^']|'')*'|x'\h*'|[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?|0x\h+|null|true|false)\z/i #: Regexp

  # @rbs return: String
  def driver = 'sqlite3'

  # @rbs return: Symbol
  def adapter_name = :sqlite

  # @rbs location: String
  # @rbs return: Skyward::ORM::_Connection
  def connect(location)
    connection = SQLite3::Database.new(location)
    connection.extended_result_codes = true
    # busy_timeout= would hold the GVL while it waits, so no other thread or
    # fiber could run, including the one holding the lock.
    connection.busy_handler_timeout = BUSY_TIMEOUT_MS
    connection.execute('PRAGMA foreign_keys = ON')
    require_version(connection.execute('SELECT sqlite_version()').dig(0, 0).to_s)
    Connection.new(connection, Skyward::ORM::Adapters::StatementCache.new)
  end

  # Each connection to :memory: opens its own empty database, so there can be
  # only the one.
  # @rbs location: String
  # @rbs size: Integer
  # @rbs return: Integer
  def pool_size(location, size) = location == ':memory:' ? 1 : size

  # @rbs version: String
  # @rbs return: void
  def require_version(version)
    return if Gem::Version.new(version) >= MINIMUM_VERSION

    raise Skyward::Core::BootError,
          "Skyward ORM needs SQLite #{MINIMUM_VERSION} or later, for RETURNING, but the sqlite3 gem loaded " \
          "SQLite #{version}. Update the sqlite3 gem, or the SQLite it's built against."
  end

  # @rbs (Integer _position) -> String
  def placeholder(_position) = '?'

  # SQLITE_MAX_VARIABLE_NUMBER's default since 3.32. A SQLite built with a
  # lower one refuses with its own error, since the sqlite3 gem doesn't expose
  # sqlite3_limit to read it.
  # @rbs return: Integer
  def bind_limit = 32_766

  # SQLite takes an OFFSET only after a LIMIT, and a negative one is no limit.
  # @rbs return: String
  def unlimited = 'LIMIT -1'

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: String?
  def sql_type(column) = SQL_TYPES[column.type]

  # An INTEGER PRIMARY KEY is SQLite's rowid, which numbers rows on its own.
  # @rbs return: String?
  def identity = nil

  # SQLite's ALTER TABLE can't change a column or a constraint, so a migration
  # rebuilds the table instead.
  # @rbs return: bool
  def alters_in_place? = false

  # SQLite takes only a literal as a default, unless the expression is in parentheses.
  # @rbs expression: String
  # @rbs return: String
  def default_expression(expression) = "(#{expression})"

  # The catalog puts back the parentheses SQLite drops, so it reads a default
  # back as it was written.
  # @rbs default: String
  # @rbs return: String
  def catalog_default(default) = default

  # SQLite stores a value by its column's affinity, which it reads from the
  # declared type, so any declared type with the same affinity is compatible,
  # and for NUMERIC_SAFE types, NUMERIC as well.
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs sql_type: String
  # @rbs return: bool
  def compatible?(column, sql_type)
    type = column.type
    expected = SQL_TYPES[type]
    declared = affinity(sql_type)
    expected.nil? || declared == affinity(expected) || (declared == :numeric && NUMERIC_SAFE.include?(type))
  end

  # A decimal's text orders "10.5" before "9.0", so a range or an order
  # compares it as a REAL, which is exact to 15 significant digits.
  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs column: String
  # @rbs return: String
  def comparable(type, column) = type == :decimal ? "CAST(#{column} AS REAL)" : column

  # @rbs sql_type: String
  # @rbs return: Skyward::ORM::Tables::column_type?
  def column_type(sql_type) = NUMERIC_NAMES[sql_type.upcase.sub(PRECISION, '')] || AFFINITY_TYPES[affinity(sql_type)]

  # @rbs value: untyped
  # @rbs return: untyped
  def encode(value)
    case value
    when true then 1
    when false then 0
    when Symbol then value.name
    # A decimal is stored as text, which = compares, so it's always written the
    # same way, without the exponent BigDecimal#to_s writes, as 0.15e1.
    # -0.0 is 0, but would be written "-0.0" and miss an = against 0 on SQLite.
    when BigDecimal then (value.zero? ? BigDecimal(0) : value).to_s('F')
    when Time then value.getutc.strftime(TIME_FORMAT)
    when Date then value.iso8601
    else value
    end
  end

  # JSON holds a boolean as one, where a column holds it as 0 or 1.
  # @rbs items: Array[untyped]
  # @rbs return: String
  def encode_array(items)
    JSON.generate(
      items.map do |item|
        case item
        when true, false then item
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

    # Of the values JSON holds, only an Array converts to one.
    "(::Array.try_convert(::JSON.parse(#{value})) || raise(::TypeError, \"\#{#{value}} isn't a JSON array\"))" \
      ".map { |item| (#{item(element, 'item')}).freeze }.freeze"
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: untyped
  def decode(column, value) = Skyward::ORM::Adapters.decode(self, column, value)

  # @rbs (Skyward::ORM::_Connection connection) -> Array[Skyward::ORM::Catalog::Table]
  def tables(connection)
    index_rows = connection.execute(INDEXES).group_by(&:first)
    connection.execute(COLUMNS).group_by(&:first).map do |name, rows|
      sql = rows.fetch(0).fetch(1)
      generated = Constraints.generated(sql)
      columns = rows.map do |_, _, column, type, not_null, primary_key, default|
        Skyward::ORM::Catalog::Column.new(
          name: column.to_sym,
          type:,
          # A primary key column can't hold NULL in practice, though SQLite only
          # enforces it for an INTEGER PRIMARY KEY or a NOT NULL column.
          nullable: not_null.zero? && primary_key.zero?,
          default: default(default),
          generated: generated[column.to_sym]
        )
      end
      Skyward::ORM::Catalog::Table.new(
        name: name.to_sym,
        columns:,
        indexes: indexes(index_rows.fetch(name, [])),
        constraints: Constraints.read(sql, columns.map(&:name))
      )
    end
  end

  # Foreign keys go off first, as SQLite's procedure for changing a table says,
  # so dropping a table the migration rebuilds doesn't cascade to the rows that
  # refer to it, and inside a transaction the PRAGMA does nothing. BEGIN
  # IMMEDIATE takes the write lock as the transaction begins rather than at its
  # first write, so a second migrator waits there, and then sees what the first ran.
  # @rbs return: String
  def begin_migration = 'PRAGMA foreign_keys = OFF; BEGIN IMMEDIATE'

  # @rbs (Skyward::ORM::_Connection connection) -> Array[String]
  def foreign_key_violations(connection)
    connection.execute('PRAGMA foreign_key_check').map do |table, rowid, parent, key|
      "#{table} row #{rowid} refers to a missing #{parent} row (foreign key #{key})"
    end
  end

  # @rbs return: String
  def end_migration = 'PRAGMA foreign_keys = ON'

  # The code says which kind of constraint failed. The message names the
  # columns of a unique or not-null one, and the name of a check, and the rest
  # comes from the schema, from the table written, or from every table when
  # raw SQL doesn't say which it writes.
  # @rbs error: StandardError
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: Symbol?
  # @rbs return: Skyward::ORM::Violation?
  def violation(error, tables, table)
    return unless error.is_a?(SQLite3::ConstraintException)

    message = error.message
    case error.code == TRIGGER && message == RESTRICTED ? :foreign_key : VIOLATIONS[error.code]
    when :unique then unique(message, tables)
    when :not_null then Skyward::ORM::Violation.new(
      kind: :not_null,
      constraint: nil,
      columns: failed_columns(message).last,
      message:
    )
    when :check then check(message, tables, table)
    when :foreign_key then foreign_key(message, tables, table)
    end
  end

  private

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: String
  # @rbs return: String
  def scalar(type, value)
    case type
    when :bool then "#{value} != 0"
    when :decimal then "BigDecimal(#{value})"
    when :date then "::Date.iso8601(#{value})"
    when :time then "::Time.new(#{value}, in: \"UTC\")"
    when :enum then "#{value}.to_sym"
    when :json then "::JSON.parse(#{value}, freeze: true)"
    # Rows are values, so even what the driver returns as it is comes back frozen.
    else "#{value}.freeze"
    end
  end

  # An Array[Float]'s JSON may hold an Integer, as an Array[Float] takes one.
  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: String
  # @rbs return: String
  def item(type, value)
    case type
    when :bool then value
    when :float then "Float(#{value})"
    # Only a String names a Symbol, and JSON may hold any value.
    when :enum then "::String.try_convert(#{value})&.to_sym"
    else scalar(type, value)
    end
  end

  # @rbs sql_type: String
  # @rbs return: Symbol
  def affinity(sql_type)
    declared = sql_type.upcase
    if declared.include?('INT') then :integer
    elsif declared.match?(/CHAR|CLOB|TEXT/) then :text
    elsif declared.empty? || declared.include?('BLOB') then :blob
    elsif declared.match?(/REAL|FLOA|DOUB/) then :real
    else :numeric
    end
  end

  # @rbs rows: Array[Array[untyped]]
  # @rbs return: Array[Skyward::ORM::Catalog::Index]
  def indexes(rows)
    rows.group_by { |row| row.fetch(1) }.map do |name, columns|
      Skyward::ORM::Catalog::Index.new(
        name:,
        # An index on an expression has no column there.
        columns: columns.filter_map { |row| row.fetch(3)&.to_sym },
        unique: columns.fetch(0).fetch(2) == 1,
        definition: columns.fetch(0).fetch(4)
      )
    end
  end

  # SQLite reads a default back without the parentheses an expression was
  # written in, so they go back on, as a migration writes them.
  # @rbs default: String?
  # @rbs return: String?
  def default(default) = default.nil? || default.match?(LITERAL) ? default : "(#{default})"

  # SQLite names a unique index on expressions rather than its columns.
  # @rbs message: String
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs return: Skyward::ORM::Violation
  def unique(message, tables)
    index = detail(message)[/\Aindex '(.*)'\z/, 1]
    if index
      found = tables.flat_map(&:indexes).find { |candidate| candidate.name == index }
      return Skyward::ORM::Violation.new(kind: :unique, constraint: index, columns: found&.columns || [], message:)
    end

    table, columns = failed_columns(message)
    written = tables.select { |candidate| candidate.name == table }
    constraints = written.flat_map(&:constraints).select { |constraint| UNIQUE_KINDS.include?(constraint.kind) }
    keys = [*constraints, *written.flat_map(&:indexes).select(&:unique)]
    key = keys.find { |candidate| candidate.columns.sort == columns.sort }
    Skyward::ORM::Violation.new(kind: :unique, constraint: key&.name, columns:, message:)
  end

  # @rbs message: String
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: Symbol?
  # @rbs return: Skyward::ORM::Violation
  def check(message, tables, table)
    name = detail(message)
    written = tables.select { |candidate| table.nil? || candidate.name == table }
    found = written.flat_map(&:constraints).find do |constraint|
      constraint.kind == :check && constraint.name == name
    end
    Skyward::ORM::Violation.new(kind: :check, constraint: name, columns: found&.columns || [], message:)
  end

  # SQLite's message names no key at all, so it's the one key the table has
  # or that refers to it. With more than one, it can't say which.
  # @rbs message: String
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: Symbol?
  # @rbs return: Skyward::ORM::Violation
  def foreign_key(message, tables, table)
    keys = tables.flat_map do |candidate|
      candidate.constraints.select do |constraint|
        constraint.kind == :foreign_key &&
          (table.nil? || candidate.name == table || constraint.references == table)
      end
    end
    key = keys.first if keys.one?
    Skyward::ORM::Violation.new(kind: :foreign_key, constraint: key&.name, columns: key&.columns || [], message:)
  end

  # SQLite names them as table.column: "UNIQUE constraint failed: todos.list_id, todos.title".
  # @rbs message: String
  # @rbs return: [Symbol, Array[Symbol]]
  def failed_columns(message)
    names = detail(message).split(', ').map { |name| name.split('.', 2) }
    [names.fetch(0).fetch(0).to_sym, names.map { |name| name.fetch(-1).to_sym }]
  end

  # @rbs message: String
  # @rbs return: String
  def detail(message) = message.split(': ', 2).last.to_s
end
