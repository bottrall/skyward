# frozen_string_literal: true

class Skyward::ORM::Connection::Session
  # @rbs @database: Skyward::ORM::Connection::Database?

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
end
