# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "sqlite3"
require "tmpdir"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::CLI::Status do
  runner = Skyward::ORM::Migrations::Runner
  sqlite = Skyward::ORM::Adapters::SQLite
  signatures = File.expand_path("../../../fixtures/migrations/sig", __dir__)
  noop = { "20261001000000_noop.sql" => "SELECT 1;\n" }

  let(:kernel) do
    Class.new do
      attr_reader :aborted, :exited

      def abort(message) = @aborted = message

      def exit(status) = @exited = status
    end.new
  end
  let(:out) { StringIO.new }

  define_method(:app) do |migrations = {}, &block|
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      database = File.join(directory, "app.sqlite3")
      File.write(
        File.join(directory, "boot.rb"),
        "Skyward.connect(#{"sqlite://#{database}".inspect}, signatures: #{signatures.inspect})\n"
      )
      FileUtils.mkdir_p(File.join(directory, "db/migrate"))
      migrations.each { |file, sql| File.write(File.join(directory, "db/migrate", file), sql) }
      block.call(directory, sqlite.connect(database))
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def run_in(directory, classes: [])
    Skyward::ORM::CLI::Status.run(
      directory:,
      out:,
      kernel:,
      session: Skyward::ORM::Connection::SESSION,
      discover: -> { classes }
    )
  end

  describe ".run" do
    it "says everything's up to date, and doesn't exit 1, once every migration has run and every class matches" do
      app(noop) do |directory, connection|
        runner.run(sqlite, connection, runner.read(File.join(directory, "db/migrate")))
        run_in(directory)

        assert_equal ["Migrations:\n  20261001000000_noop.sql  ran\n#{Skyward::ORM::Migrations::Status::CLEAN}", nil],
                     [out.string, kernel.exited]
      end
    end

    it "lists what's pending and how the classes it finds differ, and exits 1, without making schema_migrations" do
      app(noop) do |directory, connection|
        connection.execute("CREATE TABLE legacy (id INTEGER)")
        run_in(directory, classes: [MigrationsFixtures::List])
        expected = <<~TEXT
          Migrations:
            20261001000000_noop.sql  pending
          MigrationsFixtures::List has no table yet:
            + lists  2 columns
          These tables have no class, so `skyward migration` leaves them alone:
            legacy
        TEXT

        assert_equal [expected, 1, [["legacy"]]],
                     [out.string, kernel.exited,
                      connection.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")]
      end
    end

    it "shows a column that may have been renamed as one dropped and one added, since it doesn't ask" do
      app do |directory, connection|
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, title TEXT NOT NULL)")
        run_in(directory, classes: [MigrationsFixtures::List])

        assert_equal ["  - title  TEXT NOT NULL", "  + name   TEXT NOT NULL"], out.string.lines.drop(2).map(&:chomp)
      end
    end
  end
end
