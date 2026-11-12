# frozen_string_literal: true

require "stringio"
require "test_helper"
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

  # An app whose boot.rb connects to an empty database, which the block can set up first.
  def app
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      empty = TestDatabase.empty
      File.write(
        File.join(directory, "boot.rb"),
        "Skyward.connect(#{empty.url.inspect}, signatures: #{signatures.inspect})\n"
      )
      yield directory, empty.connect
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def migration_file(directory, name)
    FileUtils.mkdir_p(File.join(directory, "db/migrate"))
    File.write(File.join(directory, "db/migrate", name), "")
  end

  # A terminal that answers each question in turn, or input that isn't one.
  def terminal(*answers, tty: true)
    Class.new do
      define_method(:tty?) { tty }
      define_method(:gets) { answers.shift }
    end.new
  end

  def run_in(
    directory,
    *args,
    classes: [MigrationsFixtures::List, MigrationsFixtures::Todo],
    input: terminal(tty: false),
    generate: -> {}
  )
    Skyward::ORM::CLI::Migration.run(
      args,
      directory:,
      time: Time.utc(2026, 10, 18, 9, 30),
      input:,
      out:,
      kernel:,
      session: Skyward::ORM::Connection::SESSION,
      discover: -> { classes },
      generate:
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

    it "shows how to use it given --empty without a name" do
      app do |directory|
        run_in(directory, "--empty")

        assert_equal [migration::USAGE, []], [kernel.aborted, written(directory)]
      end
    end

    it "shows how to use it given any other flag" do
      app do |directory|
        run_in(directory, "--force", "create_todos")

        assert_equal [migration::USAGE, []], [kernel.aborted, written(directory)]
      end
    end

    it "shows how to use it given --empty twice" do
      app do |directory|
        run_in(directory, "--empty", "backfill", "--empty")

        assert_equal [migration::USAGE, []], [kernel.aborted, written(directory)]
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

    it "refuses an empty migration a name a migration already has" do
      app do |directory|
        migration_file(directory, "20261001000000_backfill.sql")
        run_in(directory, "--empty", "backfill")

        assert_equal "skyward: db/migrate/20261001000000_backfill.sql is already named backfill. Choose another name.",
                     kernel.aborted
      end
    end

    it "writes an empty migration, without regenerating or booting an app that has no boot.rb yet, and says where" do
      Dir.mktmpdir do |directory|
        run_in(directory, "--empty", "backfill_priorities", generate: -> { flunk })
        file = "db/migrate/20261018093000_backfill_priorities.sql"

        assert_equal ["Wrote #{file}. Add your SQL, then run `skyward migrate`.\n", "\n-- down\n", nil],
                     [out.string, File.read(File.join(directory, file)), kernel.aborted]
      end
    end

    it "writes an empty migration given --empty after the name" do
      Dir.mktmpdir do |directory|
        run_in(directory, "backfill_priorities", "--empty")

        assert_equal ["db/migrate/20261018093000_backfill_priorities.sql"], written(directory)
      end
    end

    it "fails with why sig/generated couldn't be regenerated, before it compares anything" do
      app do |directory|
        run_in(directory, "create_todos", generate: -> { "rbs-inline couldn't regenerate sig/generated:\n" })

        assert_equal ["rbs-inline couldn't regenerate sig/generated:\n", "", []],
                     [kernel.aborted, out.string, written(directory)]
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
        connection.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY, checksum TEXT NOT NULL)")
        connection.execute("INSERT INTO schema_migrations (version, checksum) VALUES ('20261001000000', '')")
        run_in(directory, "create_todos")

        assert_equal [nil, 2], [kernel.aborted, written(directory).size]
      end
    end

    it "fails with only the message of a class it can't migrate" do
      app do |directory|
        shared = Array.new(2) do
          Class.new(Skyward::ORM::Record) do
            table :todos
            attr_reader :id
          end
        end
        run_in(directory, "create_todos", classes: shared)

        assert_equal "#{shared.sort_by(&:to_s).join(" and ")} each declare table :todos. Give each table one class.",
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
          database.tables,
          database.adapter,
          ->(*) { false }
        )
        file = "db/migrate/20261018093000_create_todos.sql"
        expected = [
          "#{Skyward::ORM::Migrations::Summary.text(changes, database.adapter)}" \
          "Wrote #{file}. Review it, then run `skyward migrate`.\n",
          Skyward::ORM::Migrations::Script.write(changes, database.adapter),
          [Skyward::ORM::Migrations::CreateTable, Skyward::ORM::Migrations::AlterTable]
        ]

        assert_equal expected, [out.string, File.read(File.join(directory, file)), changes.map(&:class)]
      end
    end

    describe "when a column went and another came" do
      # lists has title where List has name. The migration's first line, or
      # nil when it wrote none.
      def renaming(input)
        app do |directory, connection|
          connection.execute("CREATE TABLE lists (id INTEGER CONSTRAINT lists_pkey PRIMARY KEY, title TEXT NOT NULL)")
          run_in(directory, "rename_title", classes: [MigrationsFixtures::List], input:)
          written(directory).map { |file| File.read(File.join(directory, file)).lines.first }.first
        end
      end

      it "asks whether it was renamed, and renames it on yes, in any case" do
        found = ["y\n", " YES \n"].map { |answer| renaming(terminal(answer)) }
        renamed = "ALTER TABLE lists RENAME COLUMN title TO name;\n"

        assert_equal [[renamed] * 2, "Did you rename lists.title to lists.name? [y/N] "],
                     [found, out.string.lines.first.to_s[/\A.*\] /]]
      end

      it "drops the column and adds the other on anything else, or at the end of input" do
        found = ["n\n", nil].map { |answer| renaming(terminal(answer)) }

        assert_equal ["ALTER TABLE lists DROP COLUMN title;\n"] * 2, found
      end

      it "writes nothing without a terminal to ask, and names the columns to answer for" do
        found = renaming(terminal(tty: false))

        assert_equal [
          nil,
          "skyward: did you rename lists.title to lists.name? There's no terminal to ask, so nothing was written. " \
          "Run `skyward migration` in a terminal to answer.",
          ""
        ],
                     [found, kernel.aborted, out.string]
      end
    end
  end
end
