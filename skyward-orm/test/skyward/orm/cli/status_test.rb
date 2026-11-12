# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "tmpdir"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::CLI::Status do
  runner = Skyward::ORM::Migrations::Runner
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
  let(:empty) { TestDatabase.empty }

  define_method(:app) do |migrations = {}, &block|
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(
        File.join(directory, "boot.rb"),
        "Skyward.connect(#{empty.url.inspect}, signatures: #{signatures.inspect})\n"
      )
      FileUtils.mkdir_p(File.join(directory, "db/migrate"))
      migrations.each { |file, sql| File.write(File.join(directory, "db/migrate", file), sql) }
      block.call(directory, empty.connect)
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def run_in(directory, classes: [], generate: -> {})
    Skyward::ORM::CLI::Status.run(
      directory:,
      out:,
      kernel:,
      session: Skyward::ORM::Connection::SESSION,
      discover: -> { classes },
      generate:
    )
  end

  describe ".run" do
    it "fails with why sig/generated couldn't be regenerated, before it reports" do
      app(noop) do |directory|
        run_in(directory, generate: -> { "rbs-inline couldn't regenerate sig/generated:\n" })

        assert_equal ["rbs-inline couldn't regenerate sig/generated:\n", ""], [kernel.aborted, out.string]
      end
    end

    it "says everything's up to date, and doesn't exit 1, once every migration has run and every class matches" do
      app(noop) do |directory, connection|
        runner.run(empty.adapter, connection, runner.read(File.join(directory, "db/migrate")))
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
          Run `skyward scaffold TABLE` to print a class for one.
        TEXT

        assert_equal [expected, 1, [:legacy]], [out.string, kernel.exited, empty.adapter.tables(connection).map(&:name)]
      end
    end

    it "lists what a table keeps that its class can't declare, without exiting 1 for it" do
      app do |directory, connection|
        text = empty.adapter.sql_type(TestDatabase.column(:string))
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name #{text} NOT NULL)")
        connection.execute("CREATE INDEX lists_lower_name_index ON lists (lower(name))")
        run_in(directory, classes: [MigrationsFixtures::List])
        expected = <<~TEXT
          No migrations yet.
          lists:
            lists_lower_name_index  kept: not declared by MigrationsFixtures::List
          #{Skyward::ORM::Migrations::Status::CLEAN.chomp}
        TEXT

        assert_equal [expected, nil], [out.string, kernel.exited]
      end
    end

    it "shows a column that may have been renamed as one dropped and one added, since it doesn't ask" do
      app do |directory, connection|
        text = empty.adapter.sql_type(TestDatabase.column(:string))
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, title #{text} NOT NULL)")
        run_in(directory, classes: [MigrationsFixtures::List])

        assert_equal ["  - title  #{text} NOT NULL", "  + name   #{text} NOT NULL"],
                     out.string.lines.drop(2).map(&:chomp)
      end
    end
  end
end
