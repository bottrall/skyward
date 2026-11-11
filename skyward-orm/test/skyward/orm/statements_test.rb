# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Statements do
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  webhook = TablesFixtures::Webhook

  let(:empty) { TestDatabase.empty }
  let(:adapter) { empty.adapter }
  let(:numbered) { empty.numbered }
  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }

  describe ".insert" do
    it "inserts the values given, bound as the adapter encodes them, leaving out the key, defaults and nullables" do
      expected = empty.shown(
        %(INSERT INTO "todos" ("list_id", "title", "done") VALUES (?, ?, ?)),
        [1, "Buy milk", false]
      )
      values = { list_id: 1, title: "Buy milk", done: false }

      assert_equal expected, Skyward::ORM::Statements.insert(adapter, column_types, todo, values)
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "numbers each value's placeholder" do
        sql, = Skyward::ORM::Statements.insert(adapter, column_types, todo, { list_id: 1, title: "Buy milk" })

        assert_equal %(INSERT INTO "todos" ("list_id", "title") VALUES ($1, $2)), sql
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

    it "binds a Hash for a JSON column as one value, its JSON" do
      expected = empty.shown(%(INSERT INTO "webhooks" ("settings", "payload") VALUES (?, ?)), [%({"on":true}), nil])

      assert_equal expected,
                   Skyward::ORM::Statements.insert(
                     adapter,
                     column_types,
                     webhook,
                     { settings: { "on" => true }, payload: nil }
                   )
    end

    it "leaves an untyped column to the database, inserting DEFAULT VALUES given no values" do
      note = Class.new(Skyward::ORM::Record) do
        table :notes
        attr_reader :id, :body
      end

      assert_equal [%(INSERT INTO "notes" DEFAULT VALUES), []],
                   Skyward::ORM::Statements.insert(adapter, column_types, note, {})
    end
  end

  describe ".insert_all" do
    eggs = { list_id: 1, title: "Eggs" }
    milk = { list_id: 1, title: "Milk" }

    def refused(rows) = assert_raises(ArgumentError) { insert_all(rows) }.message

    def insert_all(rows) = Skyward::ORM::Statements.insert_all(adapter, column_types, TablesFixtures::Todo, rows)

    it "inserts every row in one statement, reading each row's values in the first row's order" do
      expected = empty.shown(
        %(INSERT INTO "todos" ("list_id", "title") VALUES (?, ?), (?, ?)), [1, "Eggs", 1, "Milk"]
      )

      assert_equal expected, insert_all([eggs, { title: "Milk", list_id: 1 }])
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "numbers each value's placeholder on from the row before" do
        sql, = insert_all([eggs, milk])

        assert_equal %(INSERT INTO "todos" ("list_id", "title") VALUES ($1, $2), ($3, $4)), sql
      end
    end

    it "refuses a row with no columns, which only insert can write as a row of defaults" do
      assert_equal "TablesFixtures::Todo.insert_all row 0 has no columns. " \
                   "Use TablesFixtures::Todo.insert for a row of defaults.",
                   refused([{}, {}])
    end

    describe "with a limit on bound values" do
      let(:adapter) do
        limiting = empty.adapter
        Module.new do
          extend limiting

          def self.bind_limit = 4
        end
      end

      it "binds as many values as the limit" do
        _, binds = insert_all([eggs, milk])

        assert_equal 4, binds.size
      end

      it "refuses more values than the limit, saying to split the rows" do
        assert_equal "TablesFixtures::Todo.insert_all binds 6 values, 2 for each of 3 rows, but the database binds " \
                     "at most 4 in one statement. Split the rows, in a Skyward.transaction if they must land " \
                     "together.",
                     refused([eggs, milk, eggs])
      end
    end

    it "refuses a row with columns the first row doesn't have, or without some it has, naming each" do
      messages = [
        refused([eggs, { **milk, done: true }]),
        refused([eggs, eggs, { title: "Milk" }]),
        refused([eggs, { title: "Milk", done: true }])
      ]

      expected = [
        "TablesFixtures::Todo.insert_all row 1 has done, unlike row 0: every row needs the same columns",
        "TablesFixtures::Todo.insert_all row 2 lacks list_id, unlike row 0: every row needs the same columns",
        "TablesFixtures::Todo.insert_all row 1 has done and lacks list_id, unlike row 0: every row needs the same " \
        "columns"
      ]

      assert_equal expected, messages
    end

    it "refuses a column the class doesn't have, naming the row" do
      assert_equal "TablesFixtures::Todo.insert_all row 0: TablesFixtures::Todo has no column dnoe. " \
                   "Did you mean done?",
                   refused([{ **eggs, dnoe: true }, { **milk, dnoe: true }])
    end

    it "refuses a value its column's type doesn't take, an Array and a Range included, naming the row" do
      messages = ["yes", [true], true..true].map { |done| refused([{ **eggs, done: true }, { **milk, done: }]) }

      expected = [
        %(TablesFixtures::Todo.insert_all row 1: TablesFixtures::Todo.done is bool, not "yes" (String)),
        %(TablesFixtures::Todo.insert_all row 1: TablesFixtures::Todo.done is bool, not [true] (Array)),
        %(TablesFixtures::Todo.insert_all row 1: TablesFixtures::Todo.done is bool, not true..true (Range))
      ]

      assert_equal expected, messages
    end

    it "refuses to leave out a column that can't be NULL and has no default, naming the row" do
      assert_equal "TablesFixtures::Todo.insert_all row 0 needs list_id: a column that can't be NULL and has no " \
                   "default needs a value",
                   refused([{ title: "Eggs" }, { title: "Milk" }])
    end

    it "binds a Hash for a JSON column as its JSON, in every row" do
      rows = [{ settings: { "on" => true } }, { settings: { "on" => false } }]

      expected = empty.shown(%(INSERT INTO "webhooks" ("settings") VALUES (?), (?)), [%({"on":true}), %({"on":false})])

      assert_equal expected, Skyward::ORM::Statements.insert_all(adapter, column_types, webhook, rows)
    end
  end

  describe ".binds" do
    it "encodes each value as its column binds it" do
      values = { id: 1, settings: { "on" => true }, payload: nil }

      assert_equal [adapter.encode(1), %({"on":true}), nil],
                   Skyward::ORM::Statements.binds(adapter, column_types, webhook, values)
    end
  end

  describe ".encode" do
    def column(klass, name) = column_types.columns(klass).find { |column| column.name == name }

    it "binds a JSON column's Hash as its JSON, one value" do
      assert_equal %({"list":[1,{"ü":null}]}),
                   Skyward::ORM::Statements.encode(
                     adapter,
                     column(webhook, :settings),
                     { "list" => [1, { "ü" => nil }] }
                   )
    end

    it "binds a JSON column's nil as NULL" do
      assert_nil Skyward::ORM::Statements.encode(adapter, column(webhook, :payload), nil)
    end

    it "encodes any other column's value as the adapter does" do
      assert_equal adapter.encode(true), Skyward::ORM::Statements.encode(adapter, column(todo, :done), true)
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
