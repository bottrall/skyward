# frozen_string_literal: true

class Skyward::ORM::Connection::Database
  Held = Data.define(
    :connection, #: Skyward::ORM::_Connection
    :fiber, #: Fiber
    :transaction, #: bool
    :depth #: Integer
  )

  Statements = Data.define(
    :start, #: String
    :commit, #: Array[String]
    :rollback #: Array[String]
  )

  TRANSACTION = Statements.new(start: "BEGIN", commit: ["COMMIT"], rollback: ["ROLLBACK"]) #: Statements

  FOREIGN = "this transaction belongs to another fiber; start your own, or return the result to the block" #: String

  # @rbs @adapter: Skyward::ORM::_Adapter
  # @rbs @pool: Skyward::ORM::Connection::Pool
  # @rbs @column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs @tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs @check: bool
  # @rbs @checked: Set[singleton(Skyward::ORM::Record)]
  # @rbs @lock: Thread::Mutex
  # @rbs @decoders: Hash[[singleton(Skyward::ORM::Record), Class, Array[Symbol]], ^(Array[untyped]) -> untyped]
  # @rbs @key: Symbol

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::Connection::Pool pool,
  #   Skyward::ORM::Tables::ColumnTypes column_types, Array[Skyward::ORM::Catalog::Table] tables, check: bool) -> void
  def initialize(adapter, pool, column_types, tables, check:)
    @adapter = adapter
    @pool = pool
    @column_types = column_types
    @tables = tables
    @check = check
    @checked = Set.new
    @lock = Thread::Mutex.new
    @decoders = {}
    # Fiber storage takes only a Symbol key, and each database's transactions are its own.
    @key = :"skyward_orm_transaction_#{object_id}"
  end

  # The seam every query runs through. Fiber storage is copied into child
  # fibers and threads, so one can find a transaction here that isn't its own.
  # @rbs [T] () { (Skyward::ORM::_Connection connection) -> T } -> T
  def connection(&)
    held = Fiber[@key] #: Held?
    return @pool.with(&) unless held
    raise FiberError, FOREIGN unless owned?(held)

    yield held.connection
  end

  # @rbs [T] () { () -> T } -> T
  def transaction(&block)
    held = Fiber[@key] #: Held?
    return atomically(held.connection, held.depth + 1, &block) if held && owned?(held)

    @pool.with { |connection| atomically(connection, 0, &block) }
  end

  # @rbs return: bool
  def transaction?
    held = Fiber[@key] #: Held?
    !held.nil? && held.transaction && owned?(held)
  end

  # A transaction for code that can't wrap itself in one block, such as a
  # test's setup and teardown, until #release rolls it back. transaction?
  # doesn't report it, so code that branches on it behaves as it would untested.
  # @rbs return: void
  def hold
    connection = @pool.checkout
    Fiber[@key] = Held.new(connection:, fiber: Fiber.current, transaction: false, depth: 0)
    connection.execute(TRANSACTION.start)
  end

  # Nothing is held when #hold raised before it could take a connection.
  # @rbs return: void
  def release
    held = Fiber[@key] #: Held?
    return unless held

    Fiber[@key] = nil
    begin
      TRANSACTION.rollback.each { |sql| held.connection.execute(sql) }
    ensure
      @pool.checkin(held.connection)
    end
  end

  # @dynamic adapter
  attr_reader :adapter #: Skyward::ORM::_Adapter

  # @dynamic column_types
  attr_reader :column_types #: Skyward::ORM::Tables::ColumnTypes

  # @dynamic tables
  attr_reader :tables #: Array[Skyward::ORM::Catalog::Table]

  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Array[Array[untyped]]
  def execute(sql, binds = []) = connection { |checked_out| checked_out.execute(sql, binds) }

  # @rbs tables: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: void
  def check(tables)
    @lock.synchronize do
      unchecked = tables.reject { |table| @checked.include?(table) }
      unchecked.each { |table| Skyward::ORM::Tables::Validation.validate(table) }
      mismatches = unchecked.filter_map do |table|
        SchemaCheck.mismatch(table, @column_types.columns(table), @tables, @adapter)
      end
      raise Skyward::ORM::SchemaMismatch, mismatches.join("\n\n") unless mismatches.empty?

      @checked.merge(unchecked)
    end
  end

  # A query selects its row class's members in order, so the decoder reads
  # each value by position.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: Class
  # @rbs expressed: Array[Symbol]
  # @rbs return: ^(Array[untyped]) -> untyped
  def decoder(table, row, expressed) = @decoders[[table, row, expressed]] ||= build(table, row, expressed)

  # Every query and write calls this before it touches its table, so a table
  # class loaded after connect is checked before its first use.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs return: void
  def prepare(table)
    check([table]) if @check
  end

  # @rbs error: StandardError
  # @rbs table: Symbol?
  # @rbs return: Skyward::ORM::Violation?
  def violation(error, table) = @adapter.violation(error, @tables, table)

  # @rbs sql: String
  # @rbs values: Array[untyped]
  # @rbs return: Array[Hash[Symbol, untyped]]
  def hashes(sql, values)
    columns, rows = run(sql, values)
    rows.map { |row| columns.zip(row).to_h }
  end

  # Raw SQL picks its own columns, in its own order, so they're matched to the
  # row class's members by name.
  # @rbs row: Class
  # @rbs sql: String
  # @rbs values: Array[untyped]
  # @rbs return: Array[untyped]
  def rows(row, sql, values)
    columns, fetched = run(sql, values)
    types = @column_types.columns(row).to_h { |member| [member.name, member.type] }
    unmatched(row, columns, types.keys)
    fetched.map(&compile(row, columns, types.fetch_values(*columns)))
  end

  # @rbs migrations: Array[Skyward::ORM::Migrations::Runner::Migration]
  # @rbs return: Skyward::ORM::Migrations::Runner::outcome
  def migrate(migrations)
    changing { |checked_out| Skyward::ORM::Migrations::Runner.run(@adapter, checked_out, migrations) }
  end

  # @rbs migrations: Array[Skyward::ORM::Migrations::Runner::Migration]
  # @rbs return: Skyward::ORM::Migrations::Runner::rolled_back
  def rollback(migrations)
    changing { |checked_out| Skyward::ORM::Migrations::Runner.rollback(@adapter, checked_out, migrations) }
  end

  # The count is read on the connection that ran the write, before anything
  # else runs on it.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Integer | Skyward::ORM::Violation
  def write(table, sql, binds)
    prepare(table)
    connection do |checked_out|
      checked_out.execute(sql, binds)
      checked_out.changes
    end
  rescue StandardError => e
    violation(e, table.table_name) || raise
  end

  # RETURNING lists the row class's members in order, as its decoder reads
  # them. Steep can't tie the row class to its rows, so they're untyped here.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: Class
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Array[untyped] | Skyward::ORM::Violation
  def write_returning(table, row, sql, binds)
    # Building the decoder prepares the table, so it's built before the write runs.
    decode = decoder(table, row, [])
    execute(sql, binds).map(&decode)
  rescue StandardError => e
    violation(e, table.table_name) || raise
  end

  private

  # Migrating or rolling back changes the schema read at connect, even when a
  # later migration fails, so it's read again, and every class is checked
  # against it afresh.
  # @rbs [T] () { (Skyward::ORM::_Connection connection) -> T } -> T
  def changing
    connection do |checked_out|
      changed = yield checked_out
      tables = @adapter.tables(checked_out)
      @lock.synchronize do
        @tables = tables
        @checked.clear
      end
      changed
    end
  end

  # @rbs held: Held
  # @rbs return: bool
  def owned?(held) = held.fiber.equal?(Fiber.current)

  # @rbs [T] (Held held) { () -> T } -> T
  def within(held)
    outer = Fiber[@key] #: Held?
    Fiber[@key] = held
    begin
      yield
    ensure
      Fiber[@key] = outer
    end
  end

  # Rolled back in ensure rather than rescue, so a block left by throw or a
  # killed thread rolls back too, and so does a commit that fails, and a start
  # an exception interrupts once it has reached the database.
  # @rbs [T] (Skyward::ORM::_Connection connection, Integer depth) { () -> T } -> T
  def atomically(connection, depth)
    statements = statements(depth)
    within(Held.new(connection:, fiber: Fiber.current, transaction: true, depth:)) do
      started = false
      settled = false
      begin
        connection.execute(statements.start)
        started = true
        result = yield
        ending(statements, result).each { |sql| connection.execute(sql) }
        settled = true
        result
      ensure
        undo(connection, statements, started) unless settled
      end
    end
  end

  # Each savepoint is named by its depth, so rolling back one whose start never
  # reached the database can't roll back the one enclosing it instead.
  # @rbs depth: Integer
  # @rbs return: Statements
  def statements(depth)
    return TRANSACTION if depth.zero?

    name = "skyward_#{depth}"
    Statements.new(
      start: "SAVEPOINT #{name}",
      commit: ["RELEASE SAVEPOINT #{name}"],
      rollback: ["ROLLBACK TO SAVEPOINT #{name}", "RELEASE SAVEPOINT #{name}"]
    )
  end

  # Untyped, because Steep narrows a generic result to the violation it's
  # tested for and then can't return it as the block's type.
  # @rbs statements: Statements
  # @rbs result: untyped
  # @rbs return: Array[String]
  def ending(statements, result) = result.is_a?(Skyward::ORM::Violation) ? statements.rollback : statements.commit

  # A start that raised may not have reached the database, which then refuses
  # to roll back, so that refusal gives way to the start's own error. On
  # PostgreSQL a savepoint's refusal leaves the enclosing transaction aborted
  # until that too rolls back, which is accepted: the start's error rolls it
  # back unless a block rescues it and carries on.
  # @rbs connection: Skyward::ORM::_Connection
  # @rbs statements: Statements
  # @rbs started: bool
  # @rbs return: void
  def undo(connection, statements, started)
    statements.rollback.each { |sql| connection.execute(sql) }
  rescue StandardError
    raise if started
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: Class
  # @rbs expressed: Array[Symbol]
  # @rbs return: ^(Array[untyped]) -> untyped
  def build(table, row, expressed)
    prepare(table)
    # An expression reads no column, so without a type of its own its value passes through.
    columns = @column_types.columns(table).to_h { |column| [column.name, column.type] }.except(*expressed)
    members = @column_types.columns(row)
    types = members.map { |member| member.type == :untyped ? columns[member.name] || :untyped : member.type }
    compile(row, members.map(&:name), types)
  end

  # @rbs row: Class
  # @rbs members: Array[Symbol]
  # @rbs types: Array[Skyward::ORM::Tables::column_type]
  # @rbs return: ^(Array[untyped]) -> untyped
  def compile(row, members, types)
    lambda do |values|
      row.new(
        **members.each_with_index.to_h do |member, index|
          value = values.fetch(index)
          [member, value.nil? ? nil : @adapter.decode(types.fetch(index), value)]
        end
      )
    end
  end

  # Raw SQL returns rows, with no room for a violation, so one raises.
  # @rbs sql: String
  # @rbs values: Array[untyped]
  # @rbs return: [Array[Symbol], Array[Array[untyped]]]
  def run(sql, values)
    statement = Skyward::ORM::Statements::Placeholders.replace(sql, values.size) { |position| @adapter.placeholder(position) }
    binds = values.map { |value| @adapter.encode(value) }
    Skyward::ORM::Statements::Placeholders.require_scalars(binds, "Skyward.query")
    result = connection { |checked_out| checked_out.execute2(statement, *binds) }
    [result.fetch(0).map(&:to_sym), result.drop(1)]
  rescue StandardError => e
    violation = violation(e, nil)
    raise unless violation

    raise Skyward::ORM::ViolationError, violation
  end

  # @rbs row: Class
  # @rbs columns: Array[Symbol]
  # @rbs members: Array[Symbol]
  # @rbs return: void
  def unmatched(row, columns, members)
    extra = columns - members
    raise ArgumentError, "#{row} has no member for #{extra.join(", ")}, which the SQL returns" if extra.any?

    missing = members - columns
    raise ArgumentError, "The SQL returns no #{missing.join(", ")} for #{row}" if missing.any?
  end
end
