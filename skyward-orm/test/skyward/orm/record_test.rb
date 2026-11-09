# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Record do
  let(:list) { TablesFixtures::List.new(id: 1, name: "Home") }

  it "gives every table class the declarations" do
    assert_kind_of Skyward::ORM::Tables::Declarations, Skyward::ORM::Record
  end

  it "builds rows of no columns until a table class declares some" do
    assert_empty Skyward::ORM::Record.new.to_h
  end

  describe "querying the connected database" do
    reader = Skyward::Core::Types::Reader.new(
      Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
    )
    todo = TablesFixtures::Todo
    columns = %("id", "list_id", "title", "priority", "due_on", "done", "created_at")
    violations = {
      unique: Skyward::ORM::Violation.new(
        kind: :unique,
        constraint: "todos_title_key",
        columns: [:title],
        message: "UNIQUE constraint failed: todos.title"
      ),
      foreign_key: Skyward::ORM::Violation.new(
        kind: :foreign_key,
        constraint: "todos_list_id_fkey",
        columns: [:list_id],
        message: "FOREIGN KEY constraint failed"
      ),
      not_null: Skyward::ORM::Violation.new(
        kind: :not_null,
        constraint: nil,
        columns: [:body],
        message: "NOT NULL constraint failed: drafts.body"
      ),
      check: Skyward::ORM::Violation.new(
        kind: :check,
        constraint: "todos_title_check",
        columns: [:title],
        message: "CHECK constraint failed: todos_title_check"
      )
    }
    # A typed column refuses a nil it can't hold before any SQL runs, so only a
    # column with no type reaches the database's NOT NULL.
    draft = Class.new(Skyward::ORM::Record) do
      table :drafts
      attr_reader :id, :body
    end
    breaking = {
      unique: [todo, { list_id: 1, title: "Buy milk" }],
      foreign_key: [todo, { list_id: 9, title: "Buy eggs" }],
      not_null: [draft, { body: nil }],
      check: [todo, { list_id: 1, title: "" }]
    }

    let(:check) { false }
    let(:session) { Skyward::ORM::Connection::SESSION }
    let(:all) { Skyward::ORM::Query.new(TablesFixtures::List, session) }
    let(:milk) do
      todo.new(
        id: 1,
        list_id: 1,
        title: "Buy milk",
        priority: :normal,
        due_on: nil,
        done: false,
        created_at: Time.utc(2026, 10, 18, 9, 30)
      )
    end

    let(:connection) do
      Skyward::ORM::Adapters::SQLite.connect(":memory:").tap do |connection|
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT)")
        connection.execute("CREATE TABLE drafts (id INTEGER PRIMARY KEY, body TEXT NOT NULL)")
        connection.execute(
          "CREATE TABLE todos (id INTEGER PRIMARY KEY, " \
          "list_id INTEGER NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists, " \
          "title TEXT NOT NULL CONSTRAINT todos_title_key UNIQUE " \
          "CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200), " \
          "priority TEXT NOT NULL DEFAULT 'normal', due_on TEXT, done INTEGER NOT NULL DEFAULT 0, " \
          "created_at TEXT NOT NULL DEFAULT '2026-10-18 09:30:00.000000')"
        )
        connection.execute("INSERT INTO lists VALUES (1, 'Home')")
      end
    end

    def traced
      statements = []
      connection.trace { |sql| statements << sql }
      yield
      statements
    end

    before do
      session.connect(
        Skyward::ORM::Connection::Database.new(
          Skyward::ORM::Adapters::SQLite,
          Skyward::ORM::Connection::Pool.new(1, -> { connection }),
          Skyward::ORM::Tables::ColumnTypes.new(reader),
          Skyward::ORM::Adapters::SQLite.tables(connection),
          check:
        )
      )
    end

    describe ".all" do
      it "is a query of every row" do
        assert_equal all.to_sql, TablesFixtures::List.all.to_sql
      end

      it "asks for every row, so it can change them all" do
        assert_equal [TablesFixtures::List.new(id: 1, name: "Work")], TablesFixtures::List.all.update(name: "Work")
      end
    end

    describe ".join" do
      it "starts from every row" do
        assert_equal all.join(TablesFixtures::Todo, id: :list_id).to_sql,
                     TablesFixtures::List.join(TablesFixtures::Todo, id: :list_id).to_sql
      end
    end

    describe ".left_join" do
      it "starts from every row" do
        assert_equal all.left_join(TablesFixtures::Todo, id: :list_id).to_sql,
                     TablesFixtures::List.left_join(TablesFixtures::Todo, id: :list_id).to_sql
      end
    end

    describe ".where" do
      it "starts from every row" do
        assert_equal all.where(name: "Work").to_sql, TablesFixtures::List.where(name: "Work").to_sql
      end

      it "passes SQL on" do
        assert_equal all.where("name = ?", "Work").to_sql, TablesFixtures::List.where("name = ?", "Work").to_sql
      end
    end

    describe ".exclude" do
      it "starts from every row" do
        assert_equal all.exclude(name: "Work").to_sql, TablesFixtures::List.exclude(name: "Work").to_sql
      end
    end

    describe ".order" do
      it "starts from every row" do
        assert_equal all.order(name: :desc).to_sql, TablesFixtures::List.order(name: :desc).to_sql
      end
    end

    describe ".find_by" do
      it "starts from every row" do
        connection.execute("INSERT INTO lists VALUES (2, 'Work')")

        assert_equal all.where(name: "Work").first, TablesFixtures::List.find_by(name: "Work")
      end
    end

    describe ".insert" do
      it "inserts a row, and returns it with the database's defaults" do
        assert_equal milk, todo.insert(list_id: 1, title: "Buy milk")
      end

      it "runs one INSERT, returning the row" do
        assert_equal(
          [%(INSERT INTO "todos" ("list_id", "title") VALUES (1, 'Buy milk') RETURNING #{columns})],
          traced { todo.insert(list_id: 1, title: "Buy milk") }
        )
      end

      it "inserts the defaults given no values" do
        counter = Class.new(Skyward::ORM::Record) do
          table :counters
          attr_reader :id
        end
        connection.execute("CREATE TABLE counters (id INTEGER PRIMARY KEY)")

        assert_equal counter.new(id: 1), counter.insert
      end

      it "refuses a row missing a required column before any SQL runs" do
        assert_empty(traced { assert_raises(ArgumentError) { todo.insert(list_id: 1) } })
      end

      it "refuses an Array, which isn't one value, before any SQL runs" do
        assert_empty(traced { assert_raises(ArgumentError) { todo.insert(list_id: 1, title: ["c"]) } })
      end

      violations.each do |kind, violation|
        it "returns a #{kind} violation" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)

          assert_equal violation, table.insert(**values)
        end
      end

      describe "with the check on" do
        let(:check) { true }

        it "checks its table class before inserting" do
          notes = Class.new(Skyward::ORM::Record) do
            table :notes
            attr_reader :id
          end

          assert_raises(Skyward::ORM::SchemaMismatch) { notes.insert }
        end
      end
    end

    describe ".insert!" do
      it "returns the row it inserted" do
        assert_equal milk, todo.insert!(list_id: 1, title: "Buy milk")
      end

      violations.each do |kind, violation|
        it "raises a #{kind} violation" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)
          error = assert_raises(Skyward::ORM::ViolationError) { table.insert!(**values) }

          assert_equal violation, error.violation
        end
      end
    end
  end

  describe ".members" do
    it "is the columns, in order" do
      assert_equal %i[id name], TablesFixtures::List.members
    end
  end

  describe "#initialize" do
    it "sets the columns" do
      assert_equal({ id: 1, name: "Home" }, list.to_h)
    end

    it "freezes the row" do
      assert_predicate list, :frozen?
    end
  end

  describe "#with" do
    it "returns a copy with the changes" do
      assert_equal TablesFixtures::List.new(id: 1, name: "Work"), list.with(name: "Work")
    end

    it "leaves the row as it was" do
      list.with(name: "Work")

      assert_equal "Home", list.name
    end
  end

  describe "#deconstruct_keys" do
    it "matches a pattern" do
      matched =
        case list
        in { name: "Home" } then true
        else false
        end

      assert matched
    end

    it "is every column when every key is asked for" do
      assert_equal({ id: 1, name: "Home" }, list.deconstruct_keys(nil))
    end
  end

  describe "#inspect" do
    it "shows the class and each column" do
      todo = TablesFixtures::Todo.new(
        id: 1,
        list_id: 1,
        title: "Buy milk",
        priority: :normal,
        due_on: nil,
        done: false,
        created_at: Time.at(0, in: "UTC")
      )

      assert_equal "#<TablesFixtures::Todo id=1, list_id=1, title=\"Buy milk\", priority=:normal, due_on=nil, " \
                   "done=false, created_at=1970-01-01 00:00:00 UTC>",
                   todo.inspect
    end
  end
end
