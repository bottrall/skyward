# frozen_string_literal: true

require "open3"
require "test_helper"
require "sqlite3"
require "tmpdir"

describe "skyward/orm/commands.rb" do
  fixture = File.expand_path("../../fixtures/app", __dir__)

  def skyward(*args, chdir:)
    output, status = Open3.capture2e(Gem.ruby, Gem.bin_path("skyward-core", "skyward"), *args, chdir:)
    [output, status.exitstatus]
  end

  # A copy, so the database and migrations it writes go away with it.
  define_method(:app) do |&block|
    Dir.mktmpdir do |directory|
      FileUtils.cp_r("#{fixture}/.", directory)
      block.call(directory)
    end
  end

  describe "migration" do
    it "writes the migration for the app's table classes, though nothing has loaded them" do
      app do |directory|
        output, status = skyward("migration", "create_todos", chdir: directory)
        expected = <<~TEXT
          List has no table yet:
            + lists  2 columns
          Todo has no table yet:
            + todos  7 columns, 1 reference, 2 checks, 1 index
          Wrote db/migrate/TIMESTAMP_create_todos.sql. Review it, then run `skyward migrate`.
        TEXT

        assert_equal [expected, 0], [output.sub(/\d{14}/, "TIMESTAMP"), status]
      end
    end

    it "has nothing to write once that migration has run" do
      app do |directory|
        skyward("migration", "create_todos", chdir: directory)
        file = Dir.glob("db/migrate/*.sql", base: directory).fetch(0)
        connection = Skyward::ORM::Adapters::SQLite.connect(File.join(directory, "app.sqlite3"))
        connection.execute_batch(File.read(File.join(directory, file)).split("-- down\n").fetch(0))
        connection.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY)")
        connection.execute("INSERT INTO schema_migrations (version) VALUES (?)", [File.basename(file)[/\A\d+/]])

        assert_equal ["Every table matches its class. Nothing to write.\n", 0],
                     skyward("migration", "add_notes_to_todos", chdir: directory)
      end
    end

    it "shows how to use it, and exits 1, without a name" do
      app do |directory|
        assert_equal ["#{Skyward::ORM::CLI::Migration::USAGE}\n", 1], skyward("migration", chdir: directory)
      end
    end
  end
end
