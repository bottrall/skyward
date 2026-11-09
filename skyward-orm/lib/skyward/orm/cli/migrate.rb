# frozen_string_literal: true

module Skyward::ORM::CLI::Migrate
  extend self

  NOTHING = "No pending migrations.\n" #: String

  # @rbs (directory: String, out: _Writer, kernel: singleton(Kernel), session: Skyward::ORM::Connection::Session)
  #   -> void
  def run(directory:, out:, kernel:, session:)
    database = Skyward::ORM::CLI::BootFile.load(directory, session)
    case database
    when String then kernel.abort(database)
    else migrate(database, directory:, out:, kernel:)
    end
  # Booting the app raises it.
  rescue Skyward::Core::BootError => e
    kernel.abort(e.message)
  end

  private

  # @rbs (Skyward::ORM::Connection::Database database, directory: String, out: _Writer, kernel: singleton(Kernel))
  #   -> void
  def migrate(database, directory:, out:, kernel:)
    runner = Skyward::ORM::Migrations::Runner
    migrated = database.migrate(runner.read(File.join(directory, Skyward::ORM::Migrations::Directory::PATH)))
    case migrated
    when Array then out.write(migrated.empty? ? NOTHING : migrated.map { |version| "Migrated #{version}\n" }.join)
    else kernel.abort(runner.message(migrated))
    end
  end
end
