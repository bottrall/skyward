# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Statements do
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  columns = %("id", "list_id", "title", "priority", "due_on", "done", "created_at")

  let(:empty) { TestDatabase.empty }
  let(:adapter) { empty.adapter }
  let(:numbered) { empty.numbered }
  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }

  describe ".insert" do
    it "inserts the values given, bound as the adapter encodes them, leaving out the key, defaults and nullables" do
      expected = empty.shown(
        %(INSERT INTO "todos" ("list_id", "title", "done") VALUES (?, ?, ?) RETURNING #{columns}),
        [1, "Buy milk", false]
      )
      values = { list_id: 1, title: "Buy milk", done: false }

      assert_equal expected, Skyward::ORM::Statements.insert(adapter, column_types, todo, values)
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "numbers each value's placeholder" do
        sql, = Skyward::ORM::Statements.insert(adapter, column_types, todo, { list_id: 1, title: "Buy milk" })

        assert_equal %(INSERT INTO "todos" ("list_id", "title") VALUES ($1, $2) RETURNING #{columns}), sql
      end
    end

    it "refuses a column the class doesn't have" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.insert(adapter, column_types, todo, { list_id: 1, title: "Buy milk", dnoe: true })
      end

      assert_equal "TablesFixtures::Todo has no column dnoe. Did you mean done?", error.message
    end

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.insert(adapter, column_types, todo, { list_id: 1, title: "Buy milk", done: "yes" })
      end

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end

    it "refuses to leave out a column that can't be NULL and has no default, naming each" do
      error = assert_raises(ArgumentError) { Skyward::ORM::Statements.insert(adapter, column_types, todo, {}) }

      assert_equal "TablesFixtures::Todo.insert needs list_id, title: a column that can't be NULL and has no " \
                   "default needs a value",
                   error.message
    end

    it "leaves an untyped column to the database, inserting DEFAULT VALUES given no values" do
      note = Class.new(Skyward::ORM::Record) do
        table :notes
        attr_reader :id, :body
      end

      assert_equal [%(INSERT INTO "notes" DEFAULT VALUES RETURNING "id", "body"), []],
                   Skyward::ORM::Statements.insert(adapter, column_types, note, {})
    end
  end

  describe ".require_columns" do
    it "passes columns the table has" do
      assert_nil Skyward::ORM::Statements.require_columns(todo, %i[title done])
    end

    it "refuses a column the table doesn't have, suggesting the nearest" do
      error = assert_raises(ArgumentError) { Skyward::ORM::Statements.require_columns(todo, %i[title titel]) }

      assert_equal "TablesFixtures::Todo has no column titel. Did you mean title?", error.message
    end

    it "refuses a column with nothing to suggest" do
      error = assert_raises(ArgumentError) { Skyward::ORM::Statements.require_columns(todo, [:zzzzzz]) }

      assert_equal "TablesFixtures::Todo has no column zzzzzz.", error.message
    end
  end

  describe ".require_conditions" do
    it "passes conditions their columns' types take, unpacking an Array and a Range" do
      assert_nil Skyward::ORM::Statements.require_conditions(column_types, todo, { title: %w[a b], id: 1..5 })
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.require_conditions(column_types, todo, { titel: "Buy milk" })
      end

      assert_equal "TablesFixtures::Todo has no column titel. Did you mean title?", error.message
    end

    it "refuses the first value its column's type doesn't take" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.require_conditions(column_types, todo, { title: 1, priority: :urgent })
      end

      assert_equal "TablesFixtures::Todo.title is String, not 1 (Integer)", error.message
    end
  end

  describe ".require_values" do
    it "passes values their columns' types take" do
      assert_nil Skyward::ORM::Statements.require_values(column_types, todo, { title: "Buy milk", due_on: nil })
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.require_values(column_types, todo, { titel: "Buy milk" })
      end

      assert_equal "TablesFixtures::Todo has no column titel. Did you mean title?", error.message
    end

    it "refuses an Array, which isn't one value" do
      error = assert_raises(ArgumentError) do
        Skyward::ORM::Statements.require_values(column_types, todo, { title: ["c"] })
      end

      assert_equal %(TablesFixtures::Todo.title is String, not ["c"] (Array)), error.message
    end
  end

  describe ".returning" do
    it "returns the columns, quoted, in order" do
      assert_equal %(RETURNING "title", "order"), Skyward::ORM::Statements.returning(%i[title order])
    end
  end

  describe ".quote" do
    it "quotes a name, so a column named order is still a column" do
      assert_equal '"order"', Skyward::ORM::Statements.quote(:order)
    end

    it "escapes a double quote in a name by doubling it" do
      assert_equal '"to""dos"', Skyward::ORM::Statements.quote(:'to"dos')
    end
  end
end
