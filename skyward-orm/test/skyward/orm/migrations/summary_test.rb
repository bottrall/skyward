# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/migrations/migrations_fixtures"
require_relative "../../../fixtures/migrations/postgres"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Migrations::Summary do
  fixtures = MigrationsFixtures
  migrations = Skyward::ORM::Migrations
  sqlite = Skyward::ORM::Adapters::SQLite
  readme = File.read(File.expand_path("../../../../README.md", __dir__))
  readers = %w[migrations tables].to_h do |name|
    signatures = File.expand_path("../../../fixtures/#{name}/sig", __dir__)
    [name, Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))]
  end

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("migrations")) }

  def create(klass) = Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))

  def text(changes, adapter = Skyward::ORM::Adapters::SQLite) = Skyward::ORM::Migrations::Summary.text(changes, adapter)

  # The README's examples name the class Todo, and each ends with the line that names the file.
  def example(readme, command) = readme[/^\$ skyward migration #{command}\n(.*?)^Wrote /m, 1]

  describe ".text" do
    it "counts what a new table has, as the README's create_todos does" do
      todo = TablesFixtures::Todo
      columns = Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("tables")).columns(todo)
      summary = text([migrations::CreateTable.new(klass: todo, columns:)], MigrationsFixtures::Postgres)

      assert_equal example(readme, "create_todos"), summary.sub("TablesFixtures::", "")
    end

    it "counts only what a new table declares, one or many" do
      single = Class.new(Skyward::ORM::Record) do
        table :tags
        attr_reader :name
      end
      expected = <<~TEXT
        MigrationsFixtures::List has no table yet:
          + lists  2 columns
        MigrationsFixtures::Member has no table yet:
          + members  9 columns, 2 references, 4 checks, 2 uniques
        #{single} has no table yet:
          + tags  1 column
      TEXT

      assert_equal expected, text([create(fixtures::List), create(fixtures::Member), create(single)])
    end

    it "lists each column a table needs, as the README's add_notes_to_todos does" do
      notes = column_types.columns(fixtures::NotedTodo).select { |column| column.name == :notes }
      summary = text([migrations::AddColumns.new(klass: fixtures::NotedTodo, columns: notes)], MigrationsFixtures::Postgres)

      assert_equal example(readme, "add_notes_to_todos"), summary.sub("MigrationsFixtures::Noted", "")
    end

    it "lines up each column's type and nullability, or says it needs a type" do
      added = column_types.columns(fixtures::NotedTodo).drop(7)
      expected = <<~TEXT
        MigrationsFixtures::NotedTodo differs from the todos table:
          + notes  TEXT NULL
          + rank   INTEGER NOT NULL
          + code   TEXT NOT NULL
          + extra  needs a type
      TEXT

      assert_equal expected, text([migrations::AddColumns.new(klass: fixtures::NotedTodo, columns: added)], sqlite)
    end
  end
end
