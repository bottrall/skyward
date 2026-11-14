# frozen_string_literal: true

class Skyward::ORM::Connection::Pool
  # @rbs @size: Integer
  # @rbs @opener: ^() -> Skyward::ORM::_Connection
  # @rbs @timeout: Integer | Float
  # @rbs @idle: Thread::Queue[Skyward::ORM::_Connection | :vacant]
  # @rbs @opened: Integer
  # @rbs @mutex: Thread::Mutex

  # @rbs size: Integer
  # @rbs opener: ^() -> Skyward::ORM::_Connection
  # @rbs timeout: Integer | Float
  # @rbs return: void
  def initialize(size, opener, timeout: 5)
    @size = size
    @opener = opener
    @timeout = timeout
    @idle = Thread::Queue.new
    @opened = 0
    @mutex = Thread::Mutex.new
  end

  # @rbs [T] () { (Skyward::ORM::_Connection connection) -> T } -> T
  def with
    connection = checkout
    begin
      yield connection
    ensure
      checkin(connection)
    end
  end

  # Thread::Queue and Thread::Mutex block only the waiting fiber under a fiber
  # scheduler, so under Falcon a fiber waiting for a connection lets others run.
  # @rbs return: Skyward::ORM::_Connection
  def checkout
    take(@idle.pop(timeout: 0)) || open || take(@idle.pop(timeout: @timeout)) || raise(
      Skyward::ORM::PoolTimeout,
      "Skyward ORM waited #{@timeout} seconds for a database connection, but all #{@size} in its pool " \
      'stayed in use. Pass Skyward.connect a larger pool:, or hold each connection for less time.'
    )
  end

  # A connection can still come back mid-transaction when an exception also
  # interrupts its rollback. This runs in #with's ensure, so a rollback or
  # close that fails raises nothing to replace the block's own exception.
  # @rbs connection: Skyward::ORM::_Connection
  # @rbs return: void
  def checkin(connection)
    if reusable?(connection)
      @idle.push(connection)
    else
      @idle.push(:vacant)
      connection.close
    end
  rescue StandardError
    nil
  end

  private

  # @rbs connection: Skyward::ORM::_Connection
  # @rbs return: bool
  def reusable?(connection)
    return true unless connection.transaction_active?

    connection.execute('ROLLBACK')
    !connection.transaction_active?
  rescue StandardError
    false
  end

  # @rbs slot: Skyward::ORM::_Connection | :vacant | nil
  # @rbs return: Skyward::ORM::_Connection?
  def take(slot)
    case slot
    when :vacant then fill
    else slot
    end
  end

  # @rbs return: Skyward::ORM::_Connection
  def fill
    @opener.call
  rescue StandardError
    @idle.push(:vacant)
    raise
  end

  # The place is taken under the lock but the connection opened outside it, so a
  # slow connect holds up no other checkout.
  # @rbs return: Skyward::ORM::_Connection?
  def open
    return unless @mutex.synchronize { (@opened += 1) if @opened < @size }

    @opener.call
  rescue StandardError
    @mutex.synchronize { @opened -= 1 }
    raise
  end
end
