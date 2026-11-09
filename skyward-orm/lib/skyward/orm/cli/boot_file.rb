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
end
