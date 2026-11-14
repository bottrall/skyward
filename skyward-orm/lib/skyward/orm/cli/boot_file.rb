# frozen_string_literal: true

module Skyward::ORM::CLI::BootFile
  extend self

  FILE = 'boot.rb' #: String

  # @rbs directory: String
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs generate: ^() -> String?
  # @rbs return: Skyward::ORM::Database | String
  def load(directory, session, generate)
    path = File.join(directory, FILE)
    unless File.file?(path)
      return "skyward: no #{FILE} in #{directory}. Run skyward where your app's #{FILE} loads its table classes " \
             'and calls Skyward.connect.'
    end

    failure = generate.call
    return failure if failure

    require path
    session.database
  end

  # The migration commands are what fixes a schema that doesn't match, so they
  # boot the app with the check off.
  # @rbs directory: String
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs kernel: singleton(Kernel)
  # @rbs generate: ^() -> String?
  # @rbs &: (Skyward::ORM::Database) -> void
  # @rbs return: void
  def boot(directory, session, kernel, generate, &)
    database = session.without_check { load(directory, session, generate) }
    case database
    when String then kernel.abort(database)
    else yield database
    end
  rescue Skyward::Core::BootError => e
    kernel.abort(e.message)
  end
end
