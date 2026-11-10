# frozen_string_literal: true

require "fileutils"
require "open3"
require "test_helper"
require "tmpdir"

describe "skyward/orm/commands.rb" do
  fixture = File.expand_path("../../fixtures/app", __dir__)

  let(:empty) { TestDatabase.empty }

  def skyward(*args, chdir:)
    env = { "DATABASE_URL" => empty.url }
    output, status = Open3.capture2e(env, Gem.ruby, Gem.bin_path("skyward-core", "skyward"), *args, chdir:)
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

    it "uses sig/ as it is, and says nothing about it, in a bundle without rbs-inline, as this one is" do
      app do |directory|
        File.write(File.join(directory, "app/note.rb"), "# rbs_inline: enabled\n\nclass Note\nend\n")
        output, status = skyward("migration", "create_todos", chdir: directory)

        assert_equal [0, false, false],
                     [status, output.include?("rbs-inline"), File.exist?(File.join(directory, "sig/generated"))]
      end
    end

    it "has nothing to write once that migration has run" do
      app do |directory|
        skyward("migration", "create_todos", chdir: directory)
        skyward("migrate", chdir: directory)

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

  describe "migrate" do
    it "runs the migration skyward migration wrote, once" do
      app do |directory|
        skyward("migration", "create_todos", chdir: directory)
        ran = [skyward("migrate", chdir: directory), skyward("migrate", chdir: directory)]

        assert_equal(
          [["Migrated TIMESTAMP\n", 0], ["No pending migrations.\n", 0]],
          ran.map { |output, status| [output.sub(/\d{14}/, "TIMESTAMP"), status] }
        )
      end
    end

    it "fails without a backtrace, and exits 1, when a migration fails" do
      app do |directory|
        FileUtils.mkdir_p(File.join(directory, "db/migrate"))
        File.write(File.join(directory, "db/migrate/20261001000000_broken.sql"), "INSERT INTO nowhere VALUES (1);\n")

        message = "20261001000000_broken.sql failed, so it was rolled back and no later migration ran: " \
                  "#{empty.error("INSERT INTO nowhere VALUES (1);\n")}"

        # abort ends the line, unless the message already does.
        assert_equal ["#{message.chomp}\n", 1], skyward("migrate", chdir: directory)
      end
    end
  end

  describe "rollback" do
    def schema = empty.adapter.tables(empty.connect).reject { |table| table.name == :schema_migrations }

    it "undoes the migration skyward migration wrote, so migrating again makes the same schema" do
      app do |directory|
        skyward("migration", "create_todos", chdir: directory)
        skyward("migrate", chdir: directory)
        migrated = schema
        output, status = skyward("rollback", chdir: directory)
        rolled_back = schema
        skyward("migrate", chdir: directory)

        assert_equal [["Rolled back TIMESTAMP\n", 0], [], migrated],
                     [[output.sub(/\d{14}/, "TIMESTAMP"), status], rolled_back, schema]
      end
    end

    it "fails without a backtrace, and exits 1, when nothing has run" do
      app do |directory|
        assert_equal ["No migration has run, so there's nothing to roll back.\n", 1],
                     skyward("rollback", chdir: directory)
      end
    end
  end

  describe "status" do
    it "exits 1 while a migration is pending, and 0 once it's run" do
      app do |directory|
        skyward("migration", "create_todos", chdir: directory)
        pending = skyward("status", chdir: directory)
        skyward("migrate", chdir: directory)
        clean = skyward("status", chdir: directory)

        assert_equal(
          [
            [
              "Migrations:\n  TIMESTAMP_create_todos.sql  pending\n" \
              "List has no table yet:\n  + lists  2 columns\n" \
              "Todo has no table yet:\n  + todos  7 columns, 1 reference, 2 checks, 1 index\n",
              1
            ],
            ["Migrations:\n  TIMESTAMP_create_todos.sql  ran\n#{Skyward::ORM::Migrations::Status::CLEAN}", 0]
          ],
          [pending, clean].map { |output, status| [output.gsub(/\d{14}/, "TIMESTAMP"), status] }
        )
      end
    end
  end
end
