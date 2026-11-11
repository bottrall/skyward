# frozen_string_literal: true

class Skyward::ORM::Connection::Session
  # @rbs @database: Skyward::ORM::Database?
  # @rbs @check: bool
  # @rbs @current: Symbol
  # @rbs @holding: Symbol

  # @rbs return: void
  def initialize
    @check = true
    # Fiber storage takes only a Symbol key, and each session's switch is its own.
    @current = :"skyward_orm_database_#{object_id}"
    @holding = :"skyward_orm_holding_#{object_id}"
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs return: Skyward::ORM::Database
  def connect(database)
    @database = database
  end

  # @rbs return: Skyward::ORM::Database
  def database
    current = Fiber[@current] #: Skyward::ORM::Database?
    current || @database || raise(
      Skyward::Core::BootError,
      "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots."
    )
  end

  # Fiber storage is copied into the fibers and threads a fiber starts, so
  # those it starts in the block inherit the switch.
  # @rbs [T] (Skyward::ORM::Database database) { () -> T } -> T
  def using(database)
    outer = Fiber[@current] #: Skyward::ORM::Database?
    Fiber[@current] = database
    begin
      hold_also(database)
      yield
    ensure
      Fiber[@current] = outer
    end
  end

  # A transaction on the current database, for a test, and on each database
  # its fiber switches to, until #release rolls them all back. The holding is
  # kept before the database holds, so #release finds one that took a
  # connection and then raised.
  # @rbs return: void
  def hold
    held = database
    Thread.current[@holding] = [held]
    held.hold
  end

  # Nothing is held when #hold raised before it could find a database.
  # @rbs return: void
  def release
    holding = Thread.current[@holding] #: Array[Skyward::ORM::Database]?
    return unless holding

    Thread.current[@holding] = nil
    release_each(holding)
  end

  # @rbs return: bool
  def check? = @check

  # The migration commands boot the app in here, because the migration is what
  # fixes a schema that doesn't match, and its boot.rb connects with the default.
  # @rbs [T] () { () -> T } -> T
  def without_check
    @check = false
    yield
  ensure
    @check = true
  end

  private

  # Only the fiber that holds: the holding is fiber-local rather than in fiber
  # storage, so a fiber or thread it starts doesn't inherit it, since nothing
  # would release what one held.
  # @rbs database: Skyward::ORM::Database
  # @rbs return: void
  def hold_also(database)
    holding = Thread.current[@holding] #: Array[Skyward::ORM::Database]?
    return unless holding && !holding.include?(database)

    Thread.current[@holding] = [*holding, database]
    database.hold
  end

  # Each database is released even when one before it raises.
  # @rbs databases: Array[Skyward::ORM::Database]
  # @rbs return: void
  def release_each(databases)
    return if databases.empty?

    begin
      databases.fetch(0).release
    ensure
      release_each(databases.drop(1))
    end
  end
end
