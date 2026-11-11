# frozen_string_literal: true

require "test_helper"
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
    # The SQL beside each violation breaks it the same way, so the database
    # gives its message.
    violations = {
      unique: [
        Skyward::ORM::Violation.new(kind: :unique, constraint: "todos_title_key", columns: [:title], message: nil),
        "INSERT INTO todos (list_id, title) VALUES (1, 'Buy milk')", :todos
      ],
      foreign_key: [
        Skyward::ORM::Violation.new(
          kind: :foreign_key, constraint: "todos_list_id_fkey", columns: [:list_id], message: nil
        ),
        "INSERT INTO todos (list_id, title) VALUES (9, 'Buy eggs')", :todos
      ],
      not_null: [
        Skyward::ORM::Violation.new(kind: :not_null, constraint: nil, columns: [:body], message: nil),
        "INSERT INTO drafts (body) VALUES (NULL)", :drafts
      ],
      check: [
        Skyward::ORM::Violation.new(kind: :check, constraint: "todos_title_check", columns: [:title], message: nil),
        "INSERT INTO todos (list_id, title) VALUES (1, '')", :todos
      ]
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

    let(:empty) { TestDatabase.empty }
    let(:connection) do
      types = empty.adapter
      done, created_at = [false, milk.created_at].map do |value|
        Skyward::ORM::Migrations::Definitions.literal(types.encode(value))
      end
      empty.connect.tap do |connection|
        connection.execute("CREATE TABLE lists (id #{types.sql_type(:integer)} PRIMARY KEY, name TEXT)")
        connection.execute("CREATE TABLE drafts (id #{empty.primary_key}, body TEXT NOT NULL)")
        connection.execute(
          "CREATE TABLE todos (id #{empty.primary_key}, " \
          "list_id #{types.sql_type(:integer)} NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists, " \
          "title TEXT NOT NULL CONSTRAINT todos_title_key UNIQUE " \
          "CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200), " \
          "priority TEXT NOT NULL DEFAULT 'normal', due_on #{types.sql_type(:date)}, " \
          "done #{types.sql_type(:bool)} NOT NULL DEFAULT #{done}, " \
          "created_at #{types.sql_type(:time)} NOT NULL DEFAULT #{created_at})"
        )
        connection.execute("INSERT INTO lists VALUES (1, 'Home')")
      end
    end
    let(:sent) { [] }

    def traced
      yield
      sent
    end

    before do
      session.connect(
        Skyward::ORM::Connection::Database.new(
          empty.adapter,
          Skyward::ORM::Connection::Pool.new(1, -> { TestDatabase::Recording.new(connection:, sent:) }),
          Skyward::ORM::Tables::ColumnTypes.new(reader),
          empty.adapter.tables(connection),
          check:
        )
      )
    end

    describe ".all" do
      it "is a query of every row" do
        assert_equal all.to_sql, TablesFixtures::List.all.to_sql
      end

      it "asks for every row, so it can change them all" do
        assert_equal 1, TablesFixtures::List.all.update(name: "Work")
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

    describe ".into" do
      title = TablesFixtures::TodoTitle

      it "starts from every row" do
        assert_equal Skyward::ORM::Query.new(todo, session).into(title).to_sql, todo.into(title).to_sql
      end

      it "passes expressions on" do
        assert_equal Skyward::ORM::Query.new(todo, session).into(title, title: "upper(title)").to_sql,
                     todo.into(title, title: "upper(title)").to_sql
      end

      it "starts a query that can insert" do
        assert_equal title.new(id: 1, title: "Buy milk"), todo.into(title).insert(list_id: 1, title: "Buy milk")
      end

      it "isn't an explicit all, so it can't update or delete every row" do
        errors = [
          assert_raises(ArgumentError) { todo.into(title).update(done: true) },
          assert_raises(ArgumentError) { todo.into(title).delete }
        ]
        expected = %w[update delete].map do |method|
          "TablesFixtures::Todo can't #{method} a query with no conditions, which would change every row. " \
            "Narrow it with where or exclude, or start from TablesFixtures::Todo.all to change every row."
        end

        assert_equal expected, errors.map(&:message)
      end
    end

    describe ".insert" do
      it "inserts a row with the database's defaults, and returns how many rows it inserted" do
        inserted = todo.insert(list_id: 1, title: "Buy milk")

        assert_equal [1, [milk]], [inserted, todo.all.to_a]
      end

      it "runs one INSERT, returning nothing" do
        assert_equal(
          [empty.shown(%(INSERT INTO "todos" ("list_id", "title") VALUES (?, ?)), [1, "Buy milk"])],
          traced { todo.insert(list_id: 1, title: "Buy milk") }
        )
      end

      it "inserts the defaults given no values" do
        counter = Class.new(Skyward::ORM::Record) do
          table :counters
          attr_reader :id
        end
        connection.execute("CREATE TABLE counters (id #{empty.primary_key})")

        assert_equal [1, 1], [counter.insert, counter.all.count]
      end

      it "refuses a row missing a required column before any SQL runs" do
        assert_empty(traced { assert_raises(ArgumentError) { todo.insert(list_id: 1) } })
      end

      it "refuses an Array, which isn't one value, before any SQL runs" do
        assert_empty(traced { assert_raises(ArgumentError) { todo.insert(list_id: 1, title: ["c"]) } })
      end

      violations.each do |kind, (violation, sql, written)|
        it "returns a #{kind} violation, with the database's message" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)

          assert_equal empty.violated(violation, sql, written), table.insert(**values)
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
      it "returns how many rows it inserted" do
        assert_equal 1, todo.insert!(list_id: 1, title: "Buy milk")
      end

      violations.each do |kind, (violation, sql, written)|
        it "raises a #{kind} violation" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)
          error = assert_raises(Skyward::ORM::ViolationError) { table.insert!(**values) }

          assert_equal empty.violated(violation, sql, written), error.violation
        end
      end
    end

    describe ".insert_all" do
      rows = [{ list_id: 1, title: "Buy milk" }, { list_id: 1, title: "Buy eggs" }]

      it "inserts each row with the database's defaults, and returns how many rows it inserted" do
        inserted = todo.insert_all(rows)

        assert_equal [2, [milk, milk.with(id: 2, title: "Buy eggs")]], [inserted, todo.order(:id).to_a]
      end

      it "runs one INSERT, returning nothing" do
        assert_equal(
          [empty.shown(
            %(INSERT INTO "todos" ("list_id", "title") VALUES (?, ?), (?, ?)),
            [1, "Buy milk", 1, "Buy eggs"]
          )],
          traced { todo.insert_all(rows) }
        )
      end

      it "returns 0 for no rows, without touching the database" do
        inserted = nil
        statements = traced { inserted = todo.insert_all([]) }

        assert_equal [0, []], [inserted, statements]
      end

      it "refuses a row its insert would refuse before any SQL runs" do
        assert_empty(traced { assert_raises(ArgumentError) { todo.insert_all([*rows, { list_id: 1 }]) } })
      end

      violations.each do |kind, (violation, sql, written)|
        it "returns a #{kind} violation, with the database's message" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)

          assert_equal empty.violated(violation, sql, written), table.insert_all([values])
        end
      end

      it "inserts no row when any row breaks a constraint" do
        todo.insert_all([{ list_id: 1, title: "Buy eggs" }, { list_id: 9, title: "Buy rice" }])

        assert_equal 0, todo.all.count
      end

      describe "with the check on" do
        let(:check) { true }

        it "checks its table class before inserting" do
          notes = Class.new(Skyward::ORM::Record) do
            table :notes
            attr_reader :id
          end

          assert_raises(Skyward::ORM::SchemaMismatch) { notes.insert_all([{ id: 1 }]) }
        end
      end
    end

    describe ".insert_all!" do
      it "returns how many rows it inserted" do
        assert_equal 2, todo.insert_all!([{ list_id: 1, title: "Buy milk" }, { list_id: 1, title: "Buy eggs" }])
      end

      violations.each do |kind, (violation, sql, written)|
        it "raises a #{kind} violation" do
          todo.insert(list_id: 1, title: "Buy milk")
          table, values = breaking.fetch(kind)
          error = assert_raises(Skyward::ORM::ViolationError) { table.insert_all!([values]) }

          assert_equal empty.violated(violation, sql, written), error.violation
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
