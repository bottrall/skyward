# frozen_string_literal: true

class Skyward::ORM::Connection::Instrumented
  ONCE = "Skyward.connect's instrument: must call its block once, to run the statement" #: String

  # @rbs @connection: Skyward::ORM::_Connection
  # @rbs @instrument: Skyward::ORM::_Instrument
  # @rbs @adapter: Symbol
  # @rbs @clock_ms: ^() -> Float

  # @rbs (Skyward::ORM::_Connection connection, Skyward::ORM::_Instrument instrument, Symbol adapter,
  #   clock_ms: ^() -> Float) -> void
  def initialize(connection, instrument, adapter, clock_ms:)
    @connection = connection
    @instrument = instrument
    @adapter = adapter
    @clock_ms = clock_ms
  end

  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs prepare: bool
  # @rbs return: Array[Array[untyped]]
  def execute(sql, binds = [], prepare: false) = instrumented(sql, binds) { @connection.execute(sql, binds, prepare:) }

  # @rbs sql: String
  # @rbs *binds: untyped
  # @rbs prepare: bool
  # @rbs return: Array[Array[untyped]]
  def execute2(sql, *binds, prepare: false) = instrumented(sql, binds) { @connection.execute2(sql, *binds, prepare:) }

  # @rbs sql: String
  # @rbs return: void
  def execute_batch(sql)
    instrumented(sql, []) { @connection.execute_batch(sql) }
  end

  # @rbs return: Integer
  def changes = @connection.changes

  # @rbs return: bool
  def transaction_active? = @connection.transaction_active?

  # @rbs return: void
  def close
    @connection.close
  end

  private

  # @rbs [T] (String sql, Array[untyped] binds) { () -> T } -> T
  def instrumented(sql, binds)
    calls = 0
    # Steep can't name the method's T inside its body.
    result = nil #: untyped
    # Frozen copies, so the hook can't rewrite the SQL or the list of binds the block sends.
    execution = Skyward::ORM::Execution.new(sql: sql.dup.freeze, binds: binds.dup.freeze, adapter: @adapter)
    @instrument.call(execution) do
      calls += 1
      raise ONCE if calls > 1

      # Timed around the driver's call alone, so the hook's own work isn't counted.
      started = @clock_ms.call
      result = yield
      @clock_ms.call - started
    end
    raise ONCE if calls.zero?

    result
  end
end
