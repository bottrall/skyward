# frozen_string_literal: true

module Skyward::ORM::CLI::BootFile
  extend self

  FILE = "boot.rb" #: String

  # @rbs directory: String
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs return: Skyward::ORM::Connection::Database | String
  def load(directory, session)
    path = File.join(directory, FILE)
    unless File.file?(path)
      return "skyward: no #{FILE} in #{directory}. Run skyward where your app's #{FILE} loads its table classes " \
             "and calls Skyward.connect."
    end

    require path
    session.database
  end

  # The migration commands are what fixes a schema that doesn't match, so they
  # boot the app with the check off.
  # @rbs directory: String
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs kernel: singleton(Kernel)
  # @rbs &: (Skyward::ORM::Connection::Database) -> void
  # @rbs return: void
  def boot(directory, session, kernel, &)
    database = session.without_check { load(directory, session) }
    case database
    when String then kernel.abort(database)
    else yield database
    end
  rescue Skyward::Core::BootError => e
    kernel.abort(e.message)
  end
end
