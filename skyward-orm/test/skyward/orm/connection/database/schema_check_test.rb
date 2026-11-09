# frozen_string_literal: true

require "test_helper"
require_relative "../../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Connection::Database::SchemaCheck do
  migrate = "Run `skyward migrate`, or `skyward migration` if you haven't generated one."

  def declared(name, type, nullable: false)
    Skyward::ORM::Tables::Column.new(name:, type:, nullable:, symbols: [])
  end

  def stored(name, type, nullable: false)
    Skyward::ORM::Catalog::Column.new(name:, type:, nullable:, default: nil)
  end

  def todos(*columns)
    [Skyward::ORM::Catalog::Table.new(name: :todos, columns:, indexes: [], constraints: [])]
  end

  def mismatch(columns, tables)
    Skyward::ORM::Connection::Database::SchemaCheck.mismatch(
      TablesFixtures::Todo,
      columns,
      tables,
      Skyward::ORM::Adapters::SQLite
    )
  end

  describe ".mismatch" do
    it "is nil for a table with each column, of a compatible type and the same nullability" do
      columns = [declared(:id, :integer), declared(:due_on, :date, nullable: true)]

      assert_nil mismatch(columns, todos(stored(:id, "bigint"), stored(:due_on, "TEXT", nullable: true)))
    end

    it "ignores a column the class doesn't have" do
      assert_nil mismatch([declared(:id, :integer)], todos(stored(:id, "INTEGER"), stored(:notes, "TEXT")))
    end

    it "reports a missing table" do
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          todos  The database has no table todos.
                 #{migrate}
      MESSAGE

      assert_equal expected, mismatch([declared(:id, :integer)], [])
    end

    it "reports a missing column" do
      columns = [declared(:id, :integer), declared(:notes, :string)]
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          notes  todos has no column notes.
                 #{migrate}
      MESSAGE

      assert_equal expected, mismatch(columns, todos(stored(:id, "INTEGER")))
    end

    it "checks only that an untyped column is there" do
      assert_nil mismatch([declared(:tags, :untyped)], todos(stored(:tags, "BLOB", nullable: true)))
    end

    it "reports a type that isn't compatible" do
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          done  todos.done is TEXT, but TablesFixtures::Todo#done needs INTEGER.
                #{migrate} Or change TablesFixtures::Todo#done's type to match.
      MESSAGE

      assert_equal expected, mismatch([declared(:done, :bool)], todos(stored(:done, "TEXT")))
    end

    it "reports a column that allows NULL when the class doesn't" do
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          title  todos.title allows NULL, but TablesFixtures::Todo#title doesn't.
                 #{migrate} Or change TablesFixtures::Todo#title's type to match.
      MESSAGE

      assert_equal expected, mismatch([declared(:title, :string)], todos(stored(:title, "TEXT", nullable: true)))
    end

    it "reports a NOT NULL column when the class allows nil" do
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          due_on  todos.due_on is NOT NULL, but TablesFixtures::Todo#due_on allows nil.
                  #{migrate} Or change TablesFixtures::Todo#due_on's type to match.
      MESSAGE

      assert_equal expected, mismatch([declared(:due_on, :date, nullable: true)], todos(stored(:due_on, "TEXT")))
    end

    it "reports every problem, aligned to the longest column" do
      columns = [declared(:id, :integer), declared(:done, :bool), declared(:created_at, :time)]
      expected = <<~MESSAGE.chomp
        TablesFixtures::Todo doesn't match the todos table

          done        todos.done is TEXT, but TablesFixtures::Todo#done needs INTEGER.
                      #{migrate} Or change TablesFixtures::Todo#done's type to match.
          done        todos.done allows NULL, but TablesFixtures::Todo#done doesn't.
                      #{migrate} Or change TablesFixtures::Todo#done's type to match.
          created_at  todos has no column created_at.
                      #{migrate}
      MESSAGE

      assert_equal expected, mismatch(columns, todos(stored(:id, "INTEGER"), stored(:done, "TEXT", nullable: true)))
    end
  end
end
