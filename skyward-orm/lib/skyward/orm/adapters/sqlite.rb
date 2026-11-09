# frozen_string_literal: true

module Skyward::ORM::Adapters::SQLite
  extend self

  # The first SQLite with RETURNING, which every write uses.
  MINIMUM_VERSION = Gem::Version.new("3.35") #: Gem::Version

  SQL_TYPES = {
    integer: "INTEGER",
    float: "REAL",
    string: "TEXT",
    bool: "INTEGER",
    date: "TEXT",
    time: "TEXT",
    enum: "TEXT"
  }.freeze #: Hash[Skyward::ORM::Tables::column_type, String]

  # Fixed width and UTC, so text order is time order, and to the microsecond,
  # as PostgreSQL keeps it. It's the format of SQLite's own CURRENT_TIMESTAMP,
  # with the fraction added, so the two compare.
  TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%6N" #: String

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
  RESTRICTED = "FOREIGN KEY constraint failed" #: String

  UNIQUE_KINDS = %i[unique primary_key].freeze #: Array[Skyward::ORM::Catalog::constraint_kind]

  COLUMNS = <<~SQL #: String
    SELECT m.name, m.sql, c.name, c.type, c."notnull", c.pk
    FROM sqlite_schema AS m JOIN pragma_table_info(m.name) AS c
    WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
    ORDER BY m.name, c.cid
  SQL

  INDEXES = <<~SQL #: String
    SELECT m.name, i.name, i."unique", c.name
    FROM sqlite_schema AS m JOIN pragma_index_list(m.name) AS i JOIN pragma_index_info(i.name) AS c
    WHERE m.type = 'table' AND i.origin = 'c'
    ORDER BY m.name, i.name, c.seqno
  SQL

  # @rbs return: String
  def driver = "sqlite3"

  # @rbs location: String
  # @rbs return: Skyward::ORM::_Connection
  def connect(location)
    connection = SQLite3::Database.new(location)
    connection.extended_result_codes = true
    connection.execute("PRAGMA foreign_keys = ON")
    require_version(connection.execute("SELECT sqlite_version()").dig(0, 0).to_s)
    connection
  end

  # @rbs version: String
  # @rbs return: void
  def require_version(version)
    return if Gem::Version.new(version) >= MINIMUM_VERSION

    raise Skyward::Core::BootError,
          "Skyward ORM needs SQLite #{MINIMUM_VERSION} or later, for RETURNING, but the sqlite3 gem loaded " \
          "SQLite #{version}. Update the sqlite3 gem, or the SQLite it's built against."
  end

  # @rbs (Integer _position) -> String
  def placeholder(_position) = "?"

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs return: String?
  def sql_type(type) = SQL_TYPES[type]

  # An INTEGER PRIMARY KEY is SQLite's rowid, which numbers rows on its own.
  # @rbs return: String?
  def identity = nil

  # SQLite takes only a literal as a default, unless the expression is in parentheses.
  # @rbs expression: String
  # @rbs return: String
  def default_expression(expression) = "(#{expression})"

  # SQLite stores a value by its column's affinity, which it reads from the
  # declared type, so any declared type with the same affinity is compatible.
  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs sql_type: String
  # @rbs return: bool
  def compatible?(type, sql_type)
    expected = SQL_TYPES[type]
    expected.nil? || affinity(sql_type) == affinity(expected)
  end

  # @rbs value: untyped
  # @rbs return: untyped
  def encode(value)
    case value
    when true then 1
    when false then 0
    when Symbol then value.name
    when Time then value.getutc.strftime(TIME_FORMAT)
    when Date then value.iso8601
    else value
    end
  end

  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: untyped
  # @rbs return: untyped
  def decode(type, value)
    case type
    when :bool then value != 0
    when :date then Date.iso8601(value)
    when :time then Time.new(value, in: "UTC")
    when :enum then value.to_sym
    # Rows are values, so even what the driver returns as it is comes back frozen.
    else value.freeze
    end
  end

  # @rbs (Skyward::ORM::_Connection connection) -> Array[Skyward::ORM::Catalog::Table]
  def tables(connection)
    index_rows = connection.execute(INDEXES).group_by(&:first)
    connection.execute(COLUMNS).group_by(&:first).map do |name, rows|
      columns = rows.map do |_, _, column, type, not_null, primary_key|
        # A primary key column can't hold NULL in practice, though SQLite only
        # enforces it for an INTEGER PRIMARY KEY or a NOT NULL column.
        Skyward::ORM::Catalog::Column.new(name: column.to_sym, type:, nullable: not_null.zero? && primary_key.zero?)
      end
      Skyward::ORM::Catalog::Table.new(
        name: name.to_sym,
        columns:,
        indexes: indexes(index_rows.fetch(name, [])),
        constraints: Constraints.read(rows.fetch(0).fetch(1), columns.map(&:name))
      )
    end
  end

  # The code says which kind of constraint failed. The message names the
  # columns of a unique or not-null one, and the name of a check, and the rest
  # comes from the schema.
  # @rbs error: StandardError
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: Symbol
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

  # @rbs sql_type: String
  # @rbs return: Symbol
  def affinity(sql_type)
    declared = sql_type.upcase
    if declared.include?("INT") then :integer
    elsif declared.match?(/CHAR|CLOB|TEXT/) then :text
    elsif declared.empty? || declared.include?("BLOB") then :blob
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
        unique: columns.fetch(0).fetch(2) == 1
      )
    end
  end

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
  # @rbs table: Symbol
  # @rbs return: Skyward::ORM::Violation
  def check(message, tables, table)
    name = detail(message)
    found = tables.select { |candidate| candidate.name == table }.flat_map(&:constraints).find do |constraint|
      constraint.kind == :check && constraint.name == name
    end
    Skyward::ORM::Violation.new(kind: :check, constraint: name, columns: found&.columns || [], message:)
  end

  # SQLite's message names no key at all, so it's the one key the table has
  # or that refers to it. With more than one, it can't say which.
  # @rbs message: String
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs table: Symbol
  # @rbs return: Skyward::ORM::Violation
  def foreign_key(message, tables, table)
    keys = tables.flat_map do |candidate|
      candidate.constraints.select do |constraint|
        constraint.kind == :foreign_key && (candidate.name == table || constraint.references == table)
      end
    end
    key = keys.first if keys.one?
    Skyward::ORM::Violation.new(kind: :foreign_key, constraint: key&.name, columns: key&.columns || [], message:)
  end

  # SQLite names them as table.column: "UNIQUE constraint failed: todos.list_id, todos.title".
  # @rbs message: String
  # @rbs return: [Symbol, Array[Symbol]]
  def failed_columns(message)
    names = detail(message).split(", ").map { |name| name.split(".", 2) }
    [names.fetch(0).fetch(0).to_sym, names.map { |name| name.fetch(-1).to_sym }]
  end

  # @rbs message: String
  # @rbs return: String
  def detail(message) = message.split(": ", 2).last.to_s
end
