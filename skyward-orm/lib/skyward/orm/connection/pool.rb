# frozen_string_literal: true

class Skyward::ORM::Connection::Pool
  # @rbs @size: Integer
  # @rbs @opener: ^() -> Skyward::ORM::_Connection
  # @rbs @timeout: Integer | Float
  # @rbs @idle: Thread::Queue[Skyward::ORM::_Connection]
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
    @idle.pop(timeout: 0) || open || @idle.pop(timeout: @timeout) || raise(
      Skyward::ORM::PoolTimeout,
      "Skyward ORM waited #{@timeout} seconds for a database connection, but all #{@size} in its pool " \
      "stayed in use. Pass Skyward.connect a larger pool:, or hold each connection for less time."
    )
  end

  # @rbs connection: Skyward::ORM::_Connection
  # @rbs return: void
  def checkin(connection)
    @idle.push(connection)
  end

  private

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
