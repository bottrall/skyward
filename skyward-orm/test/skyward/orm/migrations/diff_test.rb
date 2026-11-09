# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::Migrations::Diff do
  fixtures = MigrationsFixtures
  migrations = Skyward::ORM::Migrations
  signatures = File.expand_path("../../../fixtures/migrations/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }

  def changes(classes, tables = []) = Skyward::ORM::Migrations::Diff.changes(classes, column_types, tables)

  def table(name, columns)
    Skyward::ORM::Catalog::Table.new(
      name:,
      columns: columns.map { |column| Skyward::ORM::Catalog::Column.new(name: column, type: "TEXT", nullable: true) },
      indexes: [],
      constraints: []
    )
  end

  describe ".changes" do
    it "checks each class's declarations name its columns" do
      broken = Class.new(Skyward::ORM::Record) do
        index :missing
        attr_reader :id
      end

      error = assert_raises(Skyward::Core::BootError) { changes([broken]) }

      assert_equal "#{broken} has no column missing, which its index names. " \
                   "Add `attr_reader :missing`, or fix the name.",
                   error.message
    end

    it "refuses classes that share a table" do
      error = assert_raises(Skyward::Core::BootError) { changes([fixtures::Todo, fixtures::List, fixtures::NotedTodo]) }

      assert_equal "MigrationsFixtures::NotedTodo and MigrationsFixtures::Todo each declare table :todos. " \
                   "Give each table one class.",
                   error.message
    end

    it "creates each table the database doesn't have, with its class's typed columns" do
      assert_equal [migrations::CreateTable.new(klass: fixtures::List, columns: column_types.columns(fixtures::List))],
                   changes([fixtures::List])
    end

    it "creates each new table after the new tables it references, except itself, and otherwise by name" do
      created = changes([fixtures::Attachment, fixtures::Todo, fixtures::Member, fixtures::List])

      assert_equal(%i[lists members todos attachments], created.map { |change| change.klass.table_name })
    end

    it "goes on by name when new tables reference each other" do
      second = Class.new(Skyward::ORM::Record) { table :cycle_b }
      first = Class.new(Skyward::ORM::Record) { table :cycle_a }
      first.references :b_id, second
      second.references :a_id, first
      first.attr_reader :id, :b_id
      second.attr_reader :id, :a_id

      assert_equal(%i[cycle_a cycle_b], changes([second, first]).map { |change| change.klass.table_name })
    end

    it "adds the columns a table doesn't have, after every new table" do
      todos = table(:todos, %i[id list_id title priority due_on done created_at])
      added = column_types.columns(fixtures::NotedTodo).drop(7)

      assert_equal [
        migrations::CreateTable.new(klass: fixtures::Attachment, columns: column_types.columns(fixtures::Attachment)),
        migrations::AddColumns.new(klass: fixtures::NotedTodo, columns: added)
      ],
                   changes([fixtures::NotedTodo, fixtures::Attachment], [todos])
    end

    it "has nothing for a table that has every column of its class" do
      assert_empty changes([fixtures::List], [table(:lists, %i[id name extra])])
    end
  end
end
