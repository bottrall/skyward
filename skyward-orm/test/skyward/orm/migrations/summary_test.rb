# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/migrations/migrations_fixtures"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Migrations::Summary do
  fixtures = MigrationsFixtures
  migrations = Skyward::ORM::Migrations
  catalog = Skyward::ORM::Catalog
  sqlite = Skyward::ORM::Adapters::SQLite
  postgres = Skyward::ORM::Adapters::PostgreSQL
  rework_todos = MigrationsFixtures.rework_todos
  readme = File.read(File.expand_path("../../../../README.md", __dir__))
  readers = %w[migrations tables].to_h do |name|
    signatures = File.expand_path("../../../fixtures/#{name}/sig", __dir__)
    [name, Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))]
  end

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("migrations")) }

  def create(klass) = Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))

  # A summary needs only the class and its edits.
  def alter(klass, edits)
    table = Skyward::ORM::Catalog::Table.new(name: klass.table_name, columns: [], indexes: [], constraints: [])
    Skyward::ORM::Migrations::AlterTable.new(
      klass:,
      columns: [],
      table:,
      edits:,
      kept_indexes: [],
      kept_constraints: []
    )
  end

  def text(changes, adapter = Skyward::ORM::Adapters::SQLite) = Skyward::ORM::Migrations::Summary.text(changes, adapter)

  # The README's examples name the class Todo, and each ends with the line that names the file.
  def example(readme, command) = readme[/^\$ skyward migration #{command}\n(.*?)^Wrote /m, 1]

  describe ".text" do
    it "counts what a new table has, as the README's create_todos does" do
      todo = TablesFixtures::Todo
      columns = Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("tables")).columns(todo)
      summary = text([migrations::CreateTable.new(klass: todo, columns:)], postgres)

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
      summary = text([alter(fixtures::NotedTodo, notes.map { |column| migrations::AddColumn.new(column:) })], postgres)

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

      assert_equal expected,
                   text(
                     [alter(
                       fixtures::NotedTodo,
                       added.map do |column|
                         migrations::AddColumn.new(column:)
                       end
                     )],
                     sqlite
                   )
    end

    it "marks what changes in a table, as the README's rework_todos does, after the question it asked" do
      summary = text([alter(TablesFixtures::Todo, rework_todos)], postgres)
      asked = example(readme, "rework_todos").sub(/\ADid you rename .*\n/, "")

      assert_equal asked, summary.sub("TablesFixtures::", "")
    end

    it "marks each kind of change, + for added, - for dropped and ~ for changed" do
      note = catalog::Column.new(name: :note, type: "text", nullable: true, default: nil)
      check = catalog::Constraint.new(
        name: "todos_title_check",
        kind: :check,
        columns: [:title],
        references: nil,
        definition: ""
      )
      edits = [
        migrations::DropIndex.new(
          index: catalog::Index.new(name: "todos_slug_index", columns: [:slug], unique: false, definition: "")
        ),
        migrations::DropConstraint.new(constraint: check.with(name: nil, kind: :unique, columns: %i[list_id title])),
        migrations::DropConstraint.new(constraint: check.with(name: "todos_pkey", kind: :primary_key, columns: [:id])),
        migrations::DropColumn.new(column: note),
        migrations::DropColumn.new(column: note.with(name: :raw, type: "", nullable: false)),
        migrations::ChangeType.new(column: :rank, from: "integer", to: "text"),
        migrations::ChangeNullable.new(column: :title, nullable: true),
        migrations::ChangeDefault.new(column: :done, from: nil, to: "false"),
        migrations::ChangeDefault.new(column: :priority, from: "'low'", to: nil),
        migrations::AddConstraint.new(constraint: check),
        migrations::AddConstraint.new(
          constraint: check.with(
            name: "todos_list_id_fkey",
            kind: :foreign_key,
            columns: [:list_id],
            references: :lists
          )
        )
      ]
      expected = <<~TEXT
        TablesFixtures::Todo differs from the todos table:
          - todos_slug_index    index (slug)
          - unnamed             unique (list_id, title)
          - todos_pkey          primary key (id)
          - note                text NULL
          - raw                 NOT NULL
          ~ rank                text, was integer
          ~ title               NULL, was NOT NULL
          ~ done                DEFAULT false, was no default
          ~ priority            no default, was DEFAULT 'low'
          + todos_title_check   check (title)
          + todos_list_id_fkey  reference (list_id) to lists
      TEXT

      assert_equal expected, text([alter(TablesFixtures::Todo, edits)], postgres)
    end
  end
end
