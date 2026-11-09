# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::Migrations::Status do
  status = Skyward::ORM::Migrations::Status
  runner = Skyward::ORM::Migrations::Runner
  list = MigrationsFixtures::List
  sqlite = Skyward::ORM::Adapters::SQLite
  create_a = runner.parse("20261001000000_create_a.sql", "CREATE TABLE a (id INTEGER);\n")
  create_c = runner.parse("20261003000000_create_c.sql", "CREATE TABLE c (id INTEGER);\n")
  create_lists = Skyward::ORM::Migrations::CreateTable.new(klass: list, columns: [])

  def table(name) = Skyward::ORM::Catalog::Table.new(name:, columns: [], indexes: [], constraints: [])

  describe ".migrations" do
    it "marks a migration that hasn't run as pending" do
      assert_equal [[create_a.file, :pending]], status.migrations([create_a], {})
    end

    it "marks a migration that ran with the up section it has as ran" do
      assert_equal [[create_a.file, :ran]], status.migrations([create_a], { create_a.version => create_a.checksum })
    end

    it "marks a migration whose up section changed after it ran as edited" do
      assert_equal [[create_a.file, :edited]], status.migrations([create_a], { create_a.version => "theirs" })
    end

    it "names a migration that ran but whose file is gone by its version, in order among the files" do
      ran = { create_a.version => create_a.checksum, "20261002000000" => "gone" }

      assert_equal [[create_a.file, :ran], ["20261002000000", :gone], [create_c.file, :pending]],
                   status.migrations([create_a, create_c], ran)
    end
  end

  describe ".unowned" do
    it "lists each table no class declares, but not schema_migrations" do
      tables = %i[legacy lists schema_migrations].map { |name| table(name) }

      assert_equal [:legacy], status.unowned(tables, [list])
    end
  end

  describe ".clean?" do
    it "is clean when every migration ran, every class matches its table, and every table has a class" do
      assert status.clean?([[create_a.file, :ran]], [], [])
    end

    it "isn't clean when a migration isn't simply ran" do
      refute status.clean?([[create_a.file, :ran], [create_c.file, :pending]], [], [])
    end

    it "isn't clean when a class differs from the database" do
      refute status.clean?([], [create_lists], [])
    end

    it "isn't clean when a table has no class" do
      refute status.clean?([], [], [:legacy])
    end
  end

  describe ".text" do
    it "says when there are no migrations" do
      assert_equal "No migrations yet.\n#{status::CLEAN}", status.text([], [], [], sqlite)
    end

    it "says when everything's up to date" do
      assert_equal "Migrations:\n  #{create_a.file}  ran\n#{status::CLEAN}",
                   status.text([[create_a.file, :ran]], [], [], sqlite)
    end

    it "lists each migration with its state, lined up" do
      expected = <<~TEXT
        Migrations:
          20261001000000_create_a.sql  ran
          20261002000000               ran, but its file is gone
      TEXT

      assert_equal expected, status.text([[create_a.file, :ran], ["20261002000000", :gone]], [], [], sqlite)
    end

    it "names each state" do
      states = %i[ran pending edited gone].map { |state| [create_a.file, state] }

      assert_equal(
        ["ran", "pending", "edited after it ran", "ran, but its file is gone"],
        status.text(states, [], [], sqlite).lines.drop(1).map { |line| line.split("  ").last.chomp }
      )
    end

    it "follows with how each class differs from the database, as skyward migration says, then each table with no " \
       "class" do
      expected = <<~TEXT
        Migrations:
          20261001000000_create_a.sql  pending
        #{Skyward::ORM::Migrations::Summary.text([create_lists], sqlite).chomp}
        These tables have no class, so `skyward migration` leaves them alone:
          legacy
          old_todos
      TEXT

      assert_equal expected, status.text([[create_a.file, :pending]], [create_lists], %i[legacy old_todos], sqlite)
    end
  end
end
