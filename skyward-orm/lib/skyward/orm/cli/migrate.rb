# frozen_string_literal: true

module Skyward::ORM::CLI::Migrate
  extend self

  NOTHING = "No pending migrations.\n" #: String

  # @rbs (directory: String, out: _Writer, kernel: singleton(Kernel), session: Skyward::ORM::Connection::Session,
  #   discover: ^() -> Array[singleton(Skyward::ORM::Record)], generate: ^() -> String?) -> void
  def run(directory:, out:, kernel:, session:, discover:, generate:)
    Skyward::ORM::CLI::BootFile.boot(directory, session, kernel, generate) do |database|
      migrate(database, directory:, out:, kernel:, discover:)
    end
  end

  private

  # @rbs (Skyward::ORM::Database database, directory: String, out: _Writer, kernel: singleton(Kernel),
  #   discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def migrate(database, directory:, out:, kernel:, discover:)
    runner = Skyward::ORM::Migrations::Runner
    migrated = database.migrate(runner.read(File.join(directory, Skyward::ORM::Migrations::Directory::PATH)))
    case migrated
    when Array
      out.write(migrated.empty? ? NOTHING : migrated.map { |version| "Migrated #{version}\n" }.join)
      database.check(discover.call)
    else kernel.abort(runner.message(migrated))
    end
  end
end
