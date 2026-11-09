# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "tmpdir"

describe Skyward::ORM::CLI::Migrate do
  # Loaded, so boot.rb's Skyward.connect would refuse it with the check on.
  note = Class.new(Skyward::ORM::Record) do
    table :notes
    attr_reader :id
  end
  create_notes = { "20261001000000_create_notes.sql" => "CREATE TABLE notes (id INTEGER);\n" }

  let(:kernel) do
    Class.new do
      attr_reader :aborted

      def abort(message) = @aborted = message
    end.new
  end
  let(:out) { StringIO.new }

  let(:empty) { TestDatabase.empty }

  # An app whose boot.rb connects to an empty database, with these files in db/migrate.
  def app(migrations = {})
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(
        File.join(directory, "boot.rb"),
        "Skyward.connect(#{empty.url.inspect}, signatures: #{File.join(directory, "sig").inspect})\n"
      )
      FileUtils.mkdir_p(File.join(directory, "db/migrate"))
      migrations.each { |file, sql| File.write(File.join(directory, "db/migrate", file), sql) }
      yield directory
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def run_in(directory, discover: -> { [] })
    Skyward::ORM::CLI::Migrate.run(directory:, out:, kernel:, session: Skyward::ORM::Connection::SESSION, discover:)
  end

  describe ".run" do
    it "checks the classes it finds against the tables it made" do
      app(create_notes) do |directory|
        run_in(directory, discover: -> { [note] })

        assert_equal ["Migrated 20261001000000\n", nil], [out.string, kernel.aborted]
      end
    end

    it "says when no migration is pending" do
      app do |directory|
        run_in(directory)

        assert_equal "No pending migrations.\n", out.string
      end
    end

    it "runs the pending migrations in db/migrate on boot.rb's database, printing each version" do
      migrations = {
        "20261001000000_create_a.sql" => "CREATE TABLE a (id INTEGER);\n",
        "20261002000000_create_b.sql" => "CREATE TABLE b (id INTEGER);\n"
      }
      app(migrations) do |directory|
        run_in(directory)

        assert_equal "Migrated 20261001000000\nMigrated 20261002000000\n", out.string
      end
    end

    it "prints what it migrated, then fails with only the mismatch of a class that still doesn't match" do
      app({ "20261001000000_create_a.sql" => "CREATE TABLE a (id INTEGER);\n" }) do |directory|
        run_in(directory, discover: -> { [note] })

        assert_equal ["Migrated 20261001000000\n", "#{note} doesn't match the notes table"],
                     [out.string, kernel.aborted.lines.first.chomp]
      end
    end

    it "fails with only what went wrong when a migration can't run" do
      app({ "20261001000000_broken.sql" => "INSERT INTO nowhere VALUES (1);\n" }) do |directory|
        run_in(directory)
        failed = Skyward::ORM::Migrations::Runner::Failed.new(
          file: "20261001000000_broken.sql",
          message: empty.error("INSERT INTO nowhere VALUES (1);\n")
        )

        assert_equal [Skyward::ORM::Migrations::Runner.message(failed), ""], [kernel.aborted, out.string]
      end
    end
  end
end
