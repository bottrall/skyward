# frozen_string_literal: true

require "stringio"
require "test_helper"
require "tmpdir"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::CLI::Scaffold do
  scaffold = Skyward::ORM::CLI::Scaffold
  signatures = File.expand_path("../../../fixtures/migrations/sig", __dir__)

  let(:kernel) do
    Class.new do
      attr_reader :aborted

      def abort(message) = @aborted = message
    end.new
  end
  let(:out) { StringIO.new }
  let(:empty) { TestDatabase.empty }

  # An app whose boot.rb connects to an empty database, which the block can set up first.
  define_method(:app) do |&block|
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(
        File.join(directory, "boot.rb"),
        "Skyward.connect(#{empty.url.inspect}, signatures: #{signatures.inspect})\n"
      )
      block.call(directory, empty.connect)
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def run_in(directory, *args, classes: [], generate: -> {})
    Skyward::ORM::CLI::Scaffold.run(
      args,
      directory:,
      out:,
      kernel:,
      session: Skyward::ORM::Connection::SESSION,
      discover: -> { classes },
      generate:
    )
  end

  def integer = empty.adapter.sql_type(:integer)

  def text = empty.adapter.sql_type(:string)

  def give_key = "Give the table one in a `skyward migration --empty` migration, then scaffold it."

  describe ".run" do
    it "shows how to use it, without booting, given no table, more than one, or a flag" do
      app do |directory|
        aborted = [[], %w[todos lists], ["--help"]].map do |args|
          run_in(directory, *args, generate: -> { raise "booted" })
          kernel.aborted
        end

        assert_equal [[scaffold::USAGE] * 3, ""], [aborted, out.string]
      end
    end

    it "fails with why sig/generated couldn't be regenerated" do
      app do |directory|
        run_in(directory, "todos", generate: -> { "rbs-inline couldn't regenerate sig/generated:\n" })

        assert_equal ["rbs-inline couldn't regenerate sig/generated:\n", ""], [kernel.aborted, out.string]
      end
    end

    it "refuses schema_migrations, which is Skyward ORM's own" do
      app do |directory, connection|
        connection.execute("CREATE TABLE schema_migrations (version #{text} PRIMARY KEY)")
        run_in(directory, "schema_migrations")

        assert_equal ["skyward: schema_migrations is Skyward ORM's own table, so it needs no class.", ""],
                     [kernel.aborted, out.string]
      end
    end

    it "refuses a table a loaded class already declares" do
      app do |directory, connection|
        connection.execute("CREATE TABLE lists (id #{empty.primary_key})")
        run_in(directory, "lists", classes: [MigrationsFixtures::List])

        assert_equal ["skyward: MigrationsFixtures::List already declares table :lists.", ""],
                     [kernel.aborted, out.string]
      end
    end

    it "refuses a table with no primary key" do
      app do |directory, connection|
        connection.execute("CREATE TABLE legacy (name #{text})")
        run_in(directory, "legacy")
        message = "skyward: legacy has no primary key, and a table class has a one-column primary key. #{give_key}"

        assert_equal [message, ""], [kernel.aborted, out.string]
      end
    end

    it "refuses a table whose primary key is on more than one column" do
      app do |directory, connection|
        connection.execute(
          "CREATE TABLE todos_tags (todo_id #{integer}, tag_id #{integer}, PRIMARY KEY (todo_id, tag_id))"
        )
        run_in(directory, "todos_tags")
        message = "skyward: todos_tags has a primary key on (todo_id, tag_id), and a table class has a one-column " \
                  "primary key. #{give_key}"

        assert_equal [message, ""], [kernel.aborted, out.string]
      end
    end

    it "refuses a table with a column that isn't a lowercase method name, or that a row already defines" do
      app do |directory, connection|
        connection.execute(
          %(CREATE TABLE notes (id #{empty.primary_key}, "Title" #{text}, hash #{text}, members #{text}))
        )
        run_in(directory, "notes")
        message = "skyward: a table class reads each column as a lowercase Ruby method a row doesn't already have, " \
                  "so it can't read notes.Title or notes.hash or notes.members. Rename each in a " \
                  "`skyward migration --empty` migration, then scaffold it."

        assert_equal [message, ""], [kernel.aborted, out.string]
      end
    end

    it "refuses a table the database doesn't have, suggesting a close one" do
      app do |directory, connection|
        connection.execute("CREATE TABLE todos (id #{empty.primary_key})")
        run_in(directory, "todo")

        assert_equal ["skyward: there's no table todo. Did you mean todos?", ""], [kernel.aborted, out.string]
      end
    end

    it "refuses a table the database doesn't have, with no suggestion when none is close" do
      app do |directory|
        run_in(directory, "todos")

        assert_equal ["skyward: there's no table todos.", ""], [kernel.aborted, out.string]
      end
    end

    it "prints the class for the table, with the loaded classes it references" do
      app do |directory, connection|
        connection.execute("CREATE TABLE lists (id #{empty.primary_key}, name #{text} NOT NULL)")
        connection.execute("CREATE TABLE todos (id #{empty.primary_key}, list_id #{integer} REFERENCES lists)")
        run_in(directory, "todos", classes: [MigrationsFixtures::List])
        tables = empty.adapter.tables(connection)
        todos = tables.find { |table| table.name == :todos }

        assert_equal [
          Skyward::ORM::CLI::Scaffold::Source.text(todos, tables, empty.adapter, [MigrationsFixtures::List]), nil
        ],
                     [out.string, kernel.aborted]
      end
    end
  end
end
