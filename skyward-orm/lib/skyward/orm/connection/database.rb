# frozen_string_literal: true

class Skyward::ORM::Connection::Database
  Held = Data.define(
    :connection, #: Skyward::ORM::_Connection
    :fiber, #: Fiber
    :transaction #: bool
  )

  Statements = Data.define(
    :start, #: String
    :commit, #: Array[String]
    :rollback #: Array[String]
  )

  TRANSACTION = Statements.new(start: "BEGIN", commit: ["COMMIT"], rollback: ["ROLLBACK"]) #: Statements

  # A savepoint is released even when it's rolled back to, so the innermost of
  # this name is always the block's own: SQLite and PostgreSQL both take a
  # repeated name to mean the innermost.
  SAVEPOINT = Statements.new(
    start: "SAVEPOINT skyward",
    commit: ["RELEASE SAVEPOINT skyward"],
    rollback: ["ROLLBACK TO SAVEPOINT skyward", "RELEASE SAVEPOINT skyward"]
  ) #: Statements

  FOREIGN = "this transaction belongs to another fiber; start your own, or return the result to the block" #: String

  # @rbs @adapter: Skyward::ORM::_Adapter
  # @rbs @pool: Skyward::ORM::Connection::Pool
  # @rbs @column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs @tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs @decoders: Hash[[singleton(Skyward::ORM::Record), singleton(Skyward::ORM::Record)], ^(Array[untyped]) -> Skyward::ORM::Record]
  # @rbs @key: Symbol

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::Connection::Pool pool,
  #   Skyward::ORM::Tables::ColumnTypes column_types, Array[Skyward::ORM::Catalog::Table] tables) -> void
  def initialize(adapter, pool, column_types, tables)
    @adapter = adapter
    @pool = pool
    @column_types = column_types
    @tables = tables
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
    return atomically(held.connection, SAVEPOINT, &block) if held && owned?(held)

    @pool.with { |connection| atomically(connection, TRANSACTION, &block) }
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
    Fiber[@key] = Held.new(connection:, fiber: Fiber.current, transaction: false)
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
  # @rbs return: Array[Array[untyped]]
  def execute(sql) = connection { |checked_out| checked_out.execute(sql) }

  # A query selects its row class's columns in order, so the decoder reads
  # each value by position, as its table's column type says.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: singleton(Skyward::ORM::Record)
  # @rbs return: ^(Array[untyped]) -> Skyward::ORM::Record
  def decoder(table, row) = @decoders[[table, row]] ||= build(table, row)

  # @rbs error: StandardError
  # @rbs table: Symbol
  # @rbs return: Skyward::ORM::Violation?
  def violation(error, table) = @adapter.violation(error, @tables, table)

  private

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
  # killed thread rolls back too, and so does a commit that fails.
  # @rbs [T] (Skyward::ORM::_Connection connection, Statements statements) { () -> T } -> T
  def atomically(connection, statements)
    within(Held.new(connection:, fiber: Fiber.current, transaction: true)) do
      connection.execute(statements.start)
      settled = false
      begin
        result = yield
        ending(statements, result).each { |sql| connection.execute(sql) }
        settled = true
        result
      ensure
        statements.rollback.each { |sql| connection.execute(sql) } unless settled
      end
    end
  end

  # Untyped, because Steep narrows a generic result to the violation it's
  # tested for and then can't return it as the block's type.
  # @rbs statements: Statements
  # @rbs result: untyped
  # @rbs return: Array[String]
  def ending(statements, result) = result.is_a?(Skyward::ORM::Violation) ? statements.rollback : statements.commit

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: singleton(Skyward::ORM::Record)
  # @rbs return: ^(Array[untyped]) -> Skyward::ORM::Record
  def build(table, row)
    columns = @column_types.columns(table).to_h { |column| [column.name, column.type] }
    members = row.schema.columns
    types = members.map { |member| columns[member] || :untyped } #: Array[Skyward::ORM::Tables::column_type]
    lambda do |values|
      row.new(
        **members.each_with_index.to_h do |member, index|
          value = values.fetch(index)
          [member, value.nil? ? nil : @adapter.decode(types.fetch(index), value)]
        end
      )
    end
  end
end
