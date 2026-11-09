# frozen_string_literal: true

require "fileutils"
require "stringio"
require "test_helper"
require "sqlite3"
require "tmpdir"

describe Skyward::ORM::CLI::Migrate do
  session = Skyward::ORM::Connection::SESSION

  let(:kernel) do
    Class.new do
      attr_reader :aborted

      def abort(message) = @aborted = message
    end.new
  end
  let(:out) { StringIO.new }

  # An app whose boot.rb connects to its own SQLite database, with these files in db/migrate.
  def app(migrations = {}, boot_rb: nil)
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      database = "sqlite://#{File.join(directory, "app.sqlite3")}"
      boot_rb ||= "Skyward.connect(#{database.inspect}, signatures: #{File.join(directory, "sig").inspect})\n"
      File.write(File.join(directory, "boot.rb"), boot_rb)
      FileUtils.mkdir_p(File.join(directory, "db/migrate"))
      migrations.each { |file, sql| File.write(File.join(directory, "db/migrate", file), sql) }
      yield directory
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  def run_in(directory)
    Skyward::ORM::CLI::Migrate.run(directory:, out:, kernel:, session: Skyward::ORM::Connection::SESSION)
  end

  describe ".run" do
    it "fails with what's wrong when there's no boot.rb" do
      Dir.mktmpdir do |tmp|
        directory = File.realpath(tmp)
        run_in(directory)

        assert_equal [Skyward::ORM::CLI::BootFile.load(directory, session), ""], [kernel.aborted, out.string]
      end
    end

    it "fails with only the message of a boot error, such as boot.rb not connecting" do
      boot_rb = "raise Skyward::Core::BootError, \"Skyward ORM can't connect to a URL with no scheme.\"\n"
      app(boot_rb:) do |directory|
        run_in(directory)

        assert_equal ["Skyward ORM can't connect to a URL with no scheme.", ""], [kernel.aborted, out.string]
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

    it "fails with only what went wrong when a migration can't run" do
      app({ "20261001000000_broken.sql" => "INSERT INTO nowhere VALUES (1);\n" }) do |directory|
        run_in(directory)
        failed = Skyward::ORM::Migrations::Runner::Failed.new(
          file: "20261001000000_broken.sql",
          message: "no such table: nowhere:\nINSERT INTO nowhere VALUES (1);"
        )

        assert_equal [Skyward::ORM::Migrations::Runner.message(failed), ""], [kernel.aborted, out.string]
      end
    end
  end
end
