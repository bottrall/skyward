# frozen_string_literal: true

require "delegate"
require "test_helper"
require "sqlite3"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Connection::Database do
  sqlite = Skyward::ORM::Adapters::SQLite
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))

  counting_adapter = Class.new(SimpleDelegator) do
    attr_reader :comparisons

    def compatible?(type, sql_type)
      @comparisons = comparisons.to_i + 1
      super
    end
  end

  let(:connection) do
    sqlite.connect(":memory:").tap do |connection|
      # lists.name allows NULL, which TablesFixtures::List#name doesn't.
      connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT CONSTRAINT lists_name_key UNIQUE)")
      connection.execute("INSERT INTO lists (name) VALUES ('Home')")
      connection.execute(<<~SQL)
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY, list_id INTEGER NOT NULL, title TEXT NOT NULL, priority TEXT NOT NULL,
          due_on TEXT, done INTEGER NOT NULL, created_at TEXT NOT NULL
        )
      SQL
    end
  end
  let(:adapter) { sqlite }
  let(:check) { true }
  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }
  let(:database) do
    Skyward::ORM::Connection::Database.new(adapter, connection, column_types, sqlite.tables(connection), check:)
  end
  let(:todo) { TablesFixtures::Todo }
  let(:list) { TablesFixtures::List }

  def mismatch(table)
    Skyward::ORM::Connection::Database::SchemaCheck.mismatch(
      table, column_types.columns(table), adapter.tables(connection), adapter
    )
  end

  describe "#check" do
    it "passes table classes that match the schema" do
      assert_silent { database.check([todo]) }
    end

    it "validates each class's declarations before comparing it" do
      invalid = Class.new(Skyward::ORM::Record) do
        index :done
        attr_reader :id
      end
      error = assert_raises(Skyward::Core::BootError) { database.check([invalid]) }

      assert_equal "#{invalid} has no column done, which its index names. Add `attr_reader :done`, or fix the name.",
                   error.message
    end

    it "raises SchemaMismatch with a block for each class that doesn't match" do
      missing = Class.new(Skyward::ORM::Record) do
        table :notes
        attr_reader :id
      end
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.check([todo, list, missing]) }

      assert_equal "#{mismatch(list)}\n\n#{mismatch(missing)}", error.message
    end

    describe "with an adapter that counts comparisons" do
      let(:adapter) { counting_adapter.new(sqlite) }

      it "checks a class that matches once" do
        database.check([todo])
        comparisons = adapter.comparisons
        database.check([todo])

        assert_equal comparisons, adapter.comparisons
      end

      it "checks a class that doesn't match again" do
        assert_raises(Skyward::ORM::SchemaMismatch) { database.check([list]) }
        comparisons = adapter.comparisons
        assert_raises(Skyward::ORM::SchemaMismatch) { database.check([list]) }

        assert_equal comparisons * 2, adapter.comparisons
      end
    end
  end

  describe "#adapter" do
    it "is the adapter it connected with" do
      assert_same sqlite, database.adapter
    end
  end

  describe "#column_types" do
    it "reads the column types of the signatures it was given" do
      assert_equal :enum, database.column_types.columns(todo).fetch(3).type
    end
  end

  describe "#tables" do
    it "is the schema it was given" do
      assert_equal [:lists], database.tables.map(&:name)
    end
  end

  describe "#execute" do
    it "runs SQL on its connection and returns the rows" do
      assert_equal [["Home"]], database.execute("SELECT name FROM lists")
    end
  end

  describe "#decoder" do
    let(:values) { [1, 1, "Buy milk", "normal", nil, 0, "2026-10-18 09:30:00.000000"] }

    it "checks its table class first" do
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.decoder(list, list) }

      assert_equal mismatch(list), error.message
    end

    describe "with the check off" do
      let(:check) { false }

      it "doesn't check its table class" do
        assert_equal list.new(id: 1, name: "Home"), database.decoder(list, list).call([1, "Home"])
      end
    end

    it "reads each value by its table's column type, into a row" do
      expected = todo.new(
        id: 1,
        list_id: 1,
        title: "Buy milk",
        priority: :normal,
        due_on: nil,
        done: false,
        created_at: Time.utc(2026, 10, 18, 9, 30)
      )

      assert_equal expected, database.decoder(todo, todo).call(values)
    end

    it "builds a table's decoder once" do
      assert_same database.decoder(todo, todo), database.decoder(todo, todo)
    end

    it "builds one for each row class" do
      summary = Class.new(Skyward::ORM::Record) { attr_reader :done }

      refute_same database.decoder(todo, todo), database.decoder(todo, summary)
    end

    it "reads a member of another row class by its table's column of that name" do
      summary = Class.new(Skyward::ORM::Record) { attr_reader :title, :done }

      assert_equal summary.new(title: "Buy milk", done: true), database.decoder(todo, summary).call(["Buy milk", 1])
    end

    it "passes through a member its table has no column for" do
      late = Class.new(Skyward::ORM::Record) { attr_reader :days_late }

      assert_equal late.new(days_late: 3), database.decoder(todo, late).call([3])
    end
  end

  describe "#violation" do
    def violation(sql)
      connection.execute(sql)
    rescue StandardError => e
      database.violation(e, :lists)
    end

    it "fills the violation from the schema it was given" do
      expected = Skyward::ORM::Violation.new(
        kind: :unique,
        constraint: "lists_name_key",
        columns: [:name],
        message: "UNIQUE constraint failed: lists.name"
      )

      assert_equal expected, violation("INSERT INTO lists (name) VALUES ('Home')")
    end

    it "is nil for an error that isn't a violation" do
      assert_nil violation("SELECT * FROM missing")
    end
  end
end
