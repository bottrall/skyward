# frozen_string_literal: true

class Skyward::ORM::Connection::Session
  # @rbs @database: Skyward::ORM::Connection::Database?
  # @rbs @check: bool

  # @rbs return: void
  def initialize
    @check = true
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs return: Skyward::ORM::Connection::Database
  def connect(database)
    @database = database
  end

  # @rbs return: Skyward::ORM::Connection::Database
  def database
    @database || raise(
      Skyward::Core::BootError,
      "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots."
    )
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
end
