# frozen_string_literal: true

require "stringio"
require "test_helper"
require "sqlite3"
require "tmpdir"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::CLI::Migration do
  fixtures = MigrationsFixtures
  migration = Skyward::ORM::CLI::Migration

  let(:signatures) { File.expand_path("../../../fixtures/migrations/sig", __dir__) }
  let(:kernel) do
    Class.new do
      attr_reader :aborted

      def abort(message) = @aborted = message
    end.new
  end
  let(:out) { StringIO.new }

  # An app whose boot.rb connects to its own SQLite database, which the block can set up first.
  def app(boot_rb = nil)
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      database = File.join(directory, "app.sqlite3")
      boot_rb ||= "Skyward.connect(#{"sqlite://#{database}".inspect}, signatures: #{signatures.inspect})\n"
      File.write(File.join(directory, "boot.rb"), boot_rb)
      yield directory, Skyward::ORM::Adapters::SQLite.connect(database)
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def migration_file(directory, name)
    FileUtils.mkdir_p(File.join(directory, "db/migrate"))
    File.write(File.join(directory, "db/migrate", name), "")
  end

  def run_in(directory, *args, classes: [MigrationsFixtures::List, MigrationsFixtures::Todo])
    Skyward::ORM::CLI::Migration.run(
      args,
      directory:,
      time: Time.utc(2026, 10, 18, 9, 30),
      out:,
      kernel:,
      session: Skyward::ORM::Connection::SESSION,
      discover: -> { classes }
    )
  end

  def written(directory) = Dir.glob("db/migrate/*", base: directory)

  describe ".run" do
    it "shows how to use it without a name" do
      app do |directory|
        run_in(directory)

        assert_equal [migration::USAGE, ""], [kernel.aborted, out.string]
      end
    end

    it "shows how to use it given more than a name" do
      app do |directory|
        run_in(directory, "create_todos", "now")

        assert_equal migration::USAGE, kernel.aborted
      end
    end

    it "shows how to use it given a name that isn't letters, digits and _" do
      app do |directory|
        run_in(directory, "create-todos")

        assert_equal migration::USAGE, kernel.aborted
      end
    end

    it "refuses a name a migration already has" do
      app do |directory|
        migration_file(directory, "20261001000000_create_todos.sql")
        run_in(directory, "create_todos")

        assert_equal "skyward: db/migrate/20261001000000_create_todos.sql is already named create_todos. " \
                     "Choose another name.",
                     kernel.aborted
      end
    end

    it "fails with what's wrong when there's no boot.rb" do
      Dir.mktmpdir do |tmp|
        directory = File.realpath(tmp)
        run_in(directory, "create_todos")

        assert_equal Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION), kernel.aborted
      end
    end

    it "fails with only the message of an app that doesn't boot" do
      app("raise Skyward::Core::BootError, \"Todo#tags is untyped.\"\n") do |directory|
        run_in(directory, "create_todos")

        assert_equal "Todo#tags is untyped.", kernel.aborted
      end
    end

    it "refuses while a migration hasn't run, so it can't write the same change twice" do
      app do |directory|
        migration_file(directory, "20261001000000_create_lists.sql")
        run_in(directory, "create_todos")

        assert_equal "skyward: db/migrate/20261001000000_create_lists.sql hasn't run yet. " \
                     "Run `skyward migrate` before writing the next migration.",
                     kernel.aborted
      end
    end

    it "names every migration that hasn't run" do
      app do |directory|
        migration_file(directory, "20261001000000_create_lists.sql")
        migration_file(directory, "20261002000000_create_todos.sql")
        run_in(directory, "add_notes")

        assert_equal "skyward: db/migrate/20261001000000_create_lists.sql, " \
                     "db/migrate/20261002000000_create_todos.sql haven't run yet. " \
                     "Run `skyward migrate` before writing the next migration.",
                     kernel.aborted
      end
    end

    it "goes on once every migration has run" do
      app do |directory, connection|
        migration_file(directory, "20261001000000_create_lists.sql")
        connection.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY)")
        connection.execute("INSERT INTO schema_migrations (version) VALUES ('20261001000000')")
        run_in(directory, "create_todos")

        assert_equal [nil, 2], [kernel.aborted, written(directory).size]
      end
    end

    it "fails with only the message of a class it can't migrate" do
      app do |directory|
        run_in(directory, "create_todos", classes: [fixtures::Todo, fixtures::NotedTodo])

        assert_equal "MigrationsFixtures::NotedTodo and MigrationsFixtures::Todo each declare table :todos. " \
                     "Give each table one class.",
                     kernel.aborted
      end
    end

    it "writes nothing when every table matches its class" do
      app do |directory, connection|
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
        run_in(directory, "create_lists", classes: [fixtures::List])

        assert_equal ["Every table matches its class. Nothing to write.\n", [], nil],
                     [out.string, written(directory), kernel.aborted]
      end
    end

    it "writes the migration that creates and adds what the database is missing, and says what it wrote" do
      app do |directory, connection|
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY)")
        run_in(directory, "create_todos")
        database = Skyward::ORM::Connection::SESSION.database
        changes = Skyward::ORM::Migrations::Diff.changes(
          [fixtures::List, fixtures::Todo],
          database.column_types,
          database.tables
        )
        file = "db/migrate/20261018093000_create_todos.sql"
        expected = [
          "#{Skyward::ORM::Migrations::Summary.text(changes, database.adapter)}" \
          "Wrote #{file}. Review it, then run `skyward migrate`.\n",
          Skyward::ORM::Migrations::Script.write(changes, database.adapter),
          [Skyward::ORM::Migrations::CreateTable, Skyward::ORM::Migrations::AddColumns]
        ]

        assert_equal expected, [out.string, File.read(File.join(directory, file)), changes.map(&:class)]
      end
    end
  end
end
