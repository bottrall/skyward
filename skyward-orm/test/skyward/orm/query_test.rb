# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Query do
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  list = TablesFixtures::List

  # Each write's tests break a constraint of the database. The SQL beside
  # each breaks it the same way, so the database gives its message.
  violations = {
    unique: [
      Skyward::ORM::Violation.new(kind: :unique, constraint: "lists_name_key", columns: [:name], message: nil),
      "UPDATE lists SET name = 'Home' WHERE id = 2", :lists
    ],
    foreign_key: [
      Skyward::ORM::Violation.new(
        kind: :foreign_key, constraint: "todos_list_id_fkey", columns: [:list_id], message: nil
      ),
      "UPDATE todos SET list_id = 9 WHERE id = 2", :todos
    ],
    not_null: [
      Skyward::ORM::Violation.new(kind: :not_null, constraint: nil, columns: [:body], message: nil),
      "UPDATE drafts SET body = NULL WHERE id = 2", :drafts
    ],
    check: [
      Skyward::ORM::Violation.new(kind: :check, constraint: "todos_title_check", columns: [:title], message: nil),
      "UPDATE todos SET title = '' WHERE id = 2", :todos
    ]
  }
  # A typed column refuses a nil it can't hold before any SQL runs, so only a
  # column with no type reaches the database's NOT NULL.
  draft = Class.new(Skyward::ORM::Record) do
    table :drafts
    attr_reader :id, :body
  end
  breaking = {
    unique: [TablesFixtures::List, { name: "Home" }],
    foreign_key: [todo, { list_id: 9 }],
    not_null: [draft, { body: nil }],
    check: [todo, { title: "" }]
  }

  let(:empty) { TestDatabase.empty }
  let(:adapter) { empty.adapter }
  let(:numbered) { empty.numbered }
  let(:check) { false }
  let(:connection) do
    types = empty.adapter
    integer = types.sql_type(:integer)
    empty.connect.tap do |connection|
      connection.execute("CREATE TABLE lists (id #{integer} PRIMARY KEY, name TEXT CONSTRAINT lists_name_key UNIQUE)")
      connection.execute("INSERT INTO lists VALUES (1, 'Home'), (2, 'Work')")
      connection.execute("CREATE TABLE drafts (id #{integer} PRIMARY KEY, body TEXT NOT NULL)")
      connection.execute(
        "CREATE TABLE todos (id #{integer} PRIMARY KEY, " \
        "list_id #{integer} CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE RESTRICT, " \
        "title TEXT NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200), " \
        "priority TEXT, due_on #{types.sql_type(:date)}, done #{types.sql_type(:bool)}, " \
        "created_at #{types.sql_type(:time)})"
      )
    end
  end
  let(:sent) { [] }
  let(:session) do
    Skyward::ORM::Connection::Session.new.tap do |session|
      session.connect(
        Skyward::ORM::Database.new(
          adapter,
          Skyward::ORM::Connection::Pool.new(1, -> { TestDatabase::Recording.new(connection:, sent:) }),
          Skyward::ORM::Tables::ColumnTypes.new(reader),
          empty.adapter.tables(connection),
          check:
        )
      )
    end
  end
  let(:query) { Skyward::ORM::Query.new(todo, session) }
  let(:notes) do
    Class.new(Skyward::ORM::Record) do
      table :notes
      attr_reader :id
    end
  end
  let(:milk) do
    todo.new(
      id: 1,
      list_id: nil,
      title: "Buy milk",
      priority: :high,
      due_on: nil,
      done: false,
      created_at: Time.utc(2026, 10, 18, 9, 30)
    )
  end
  let(:eggs) { milk.with(id: 2, title: "Buy eggs", priority: :normal, due_on: Date.new(2026, 10, 20), done: true) }

  def insert(*rows)
    rows.each do |row|
      placeholders = Array.new(row.to_h.size) { |index| adapter.placeholder(index + 1) }
      connection.execute(
        %(INSERT INTO "#{row.class.table_name}" VALUES (#{placeholders.join(", ")})),
        row.to_h.values.map { |value| adapter.encode(value) }
      )
    end
  end

  def traced
    yield
    sent
  end

  describe "#update" do
    before { insert(milk, eggs, draft.new(id: 2, body: "Cold")) }

    it "sets the values on the rows that match, and returns how many it changed" do
      updated = query.where(id: 2).update(title: "Buy bread", done: false)

      assert_equal [1, [milk, eggs.with(title: "Buy bread", done: false)]], [updated, query.order(:id).to_a]
    end

    it "runs one UPDATE, returning nothing" do
      assert_equal(
        [empty.shown(%(UPDATE "todos" SET "done" = ? WHERE "id" = ?), [true, 1])],
        traced { query.where(id: 1).update(done: true) }
      )
    end

    it "returns 0 when no row matches" do
      assert_equal 0, query.where(id: 3).update(done: true)
    end

    it "updates the rows an explicit all's exclude leaves" do
      assert_equal(
        [empty.shown(%(UPDATE "todos" SET "title" = ? WHERE NOT ("done" = ?)), ["Buy bread", true])],
        traced { Skyward::ORM::Query.new(todo, session, scope: :all).exclude(done: true).update(title: "Buy bread") }
      )
    end

    it "updates the rows a where or an or matches, grouping a range's ends" do
      assert_equal(
        [
          empty.shown(
            %(UPDATE "todos" SET "done" = ? WHERE ("id" >= ? AND "id" <= ?) OR "title" = ?),
            [false, 1, 1, "Buy eggs"]
          )
        ],
        traced { query.where(id: 1..1).or(title: "Buy eggs").update(done: false) }
      )
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "numbers its where's placeholders after the values it sets" do
        query.where(id: 2, done: true).update(title: "Buy bread")

        assert_equal [milk, eggs.with(title: "Buy bread")], query.order(:id).to_a
      end

      it "numbers an or's and a range's placeholders after the values it sets" do
        query.where(id: 1..1).or(title: "Buy eggs").update(title: "Buy bread", done: false)

        assert_equal [milk.with(title: "Buy bread"), eggs.with(title: "Buy bread", done: false)], query.order(:id).to_a
      end
    end

    it "refuses no values" do
      error = assert_raises(ArgumentError) { query.where(id: 1).update }

      assert_equal "TablesFixtures::Todo update needs a column to set, such as update(done: true)", error.message
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) { query.where(id: 1).update(dnoe: true) }

      assert_equal "TablesFixtures::Todo has no column dnoe. Did you mean done?", error.message
    end

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) { query.where(id: 1).update(done: "yes") }

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end

    it "refuses an Array, which isn't one value, before any SQL runs" do
      assert_empty(traced { assert_raises(ArgumentError) { query.where(id: 2).update(title: ["c"]) } })
    end

    it "refuses an order, which PostgreSQL and SQLite don't both support" do
      error = assert_raises(ArgumentError) { query.where(id: 1).order(:title).update(done: true) }

      assert_equal "TablesFixtures::Todo can't update a query with order, " \
                   "which PostgreSQL and SQLite don't both support",
                   error.message
    end

    it "refuses a join, order, group, limit or offset, naming each" do
      error = assert_raises(ArgumentError) do
        query.join(list, list_id: :id).where(id: 1).order(:title).group(:done).limit(1).offset(1).update(done: true)
      end

      assert_equal "TablesFixtures::Todo can't update a query with join, order, group, limit or offset, " \
                   "which PostgreSQL and SQLite don't both support",
                   error.message
    end

    it "refuses a join before any SQL runs" do
      joined_query = query.join(list, list_id: :id).where(id: 1)

      assert_empty(traced { assert_raises(ArgumentError) { joined_query.update(done: true) } })
    end

    it "refuses a query with no conditions, which would change every row" do
      error = assert_raises(ArgumentError) { query.update(done: true) }

      assert_equal "TablesFixtures::Todo can't update a query with no conditions, which would change every row. " \
                   "Narrow it with where or exclude, or start from TablesFixtures::Todo.all to change every row.",
                   error.message
    end

    it "changes every row of an explicit all" do
      assert_equal [2, [milk.with(done: true), eggs]],
                   [Skyward::ORM::Query.new(todo, session, scope: :all).update(done: true), query.order(:id).to_a]
    end

    violations.each do |kind, (violation, sql, written)|
      it "returns a #{kind} violation, with the database's message" do
        table, values = breaking.fetch(kind)

        assert_equal empty.violated(violation, sql, written),
                     Skyward::ORM::Query.new(table, session).where(id: 2).update(**values)
      end
    end

    describe "with the check on" do
      let(:check) { true }

      it "checks its table class before writing" do
        assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, session).where(id: 1).update(id: 2) }
      end
    end
  end

  describe "#update!" do
    before { insert(milk, eggs) }

    it "returns how many rows it changed" do
      assert_equal 1, query.where(id: 1).update!(done: true)
    end

    it "raises the violation update returns" do
      lists = Skyward::ORM::Query.new(TablesFixtures::List, session)
      error = assert_raises(Skyward::ORM::ViolationError) { lists.where(id: 2).update!(name: "Home") }

      assert_equal empty.violated(*violations.fetch(:unique)), error.violation
    end
  end

  describe "#delete" do
    before { insert(milk.with(list_id: 1), eggs) }

    it "deletes the rows that match, and returns how many it deleted" do
      deleted = query.where(done: true).delete

      assert_equal [1, [milk.with(list_id: 1)]], [deleted, query.to_a]
    end

    it "runs one DELETE, returning nothing" do
      assert_equal([empty.shown(%(DELETE FROM "todos" WHERE "id" = ?), [2])], traced { query.where(id: 2).delete })
    end

    it "returns 0 when no row matches" do
      assert_equal 0, query.where(id: 3).delete
    end

    it "deletes the rows an explicit all's exclude leaves" do
      Skyward::ORM::Query.new(todo, session, scope: :all).exclude(done: false).delete

      assert_equal [milk.with(list_id: 1)], query.to_a
    end

    it "deletes the rows a where or an or matches, grouping a range's ends" do
      assert_equal(
        [
          empty.shown(%(DELETE FROM "todos" WHERE ("id" >= ? AND "id" <= ?) OR "title" = ?), [2, 2, "Buy bread"])
        ],
        traced { query.where(id: 2..2).or(title: "Buy bread").delete }
      )
    end

    it "refuses a left join before any SQL runs" do
      joined_query = query.left_join(list, list_id: :id).where(id: 1)

      assert_empty(traced { assert_raises(ArgumentError) { joined_query.delete } })
    end

    it "refuses a limit or offset, naming delete" do
      error = assert_raises(ArgumentError) { query.where(done: true).limit(1).offset(1).delete }

      assert_equal "TablesFixtures::Todo can't delete a query with limit or offset, " \
                   "which PostgreSQL and SQLite don't both support",
                   error.message
    end

    it "refuses a query with no conditions, naming delete" do
      error = assert_raises(ArgumentError) { query.delete }

      assert_equal "TablesFixtures::Todo can't delete a query with no conditions, which would change every row. " \
                   "Narrow it with where or exclude, or start from TablesFixtures::Todo.all to change every row.",
                   error.message
    end

    it "deletes every row of an explicit all" do
      assert_equal [2, []], [Skyward::ORM::Query.new(todo, session, scope: :all).delete, query.to_a]
    end

    it "refuses an explicit all that a where or an exclude given nothing narrowed" do
      all = Skyward::ORM::Query.new(todo, session, scope: :all)

      assert_raises(ArgumentError) { all.where.delete }
      assert_raises(ArgumentError) { all.exclude.delete }
    end

    it "refuses a merge unless both sides are an explicit all that nothing narrowed" do
      all = Skyward::ORM::Query.new(todo, session, scope: :all)
      merged = [all.merge(all.where), all.where.merge(all), all.merge(query)]

      assert(merged.all? { |each| assert_raises(ArgumentError) { each.delete }.message.include?("no conditions") })
    end

    it "deletes every row of two explicit alls merged" do
      all = Skyward::ORM::Query.new(todo, session, scope: :all)

      assert_equal [2, []], [all.merge(all).delete, query.to_a]
    end

    it "returns the violation of a row another restricts" do
      restricted = violations.fetch(:foreign_key).fetch(0)

      assert_equal empty.violated(restricted, "DELETE FROM lists WHERE id = 1", :lists),
                   Skyward::ORM::Query.new(TablesFixtures::List, session).where(id: 1).delete
    end

    describe "with the check on" do
      let(:check) { true }

      it "checks its table class before writing" do
        assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, session).where(id: 1).delete }
      end
    end
  end

  describe "#delete!" do
    before { insert(milk.with(list_id: 1), eggs) }

    it "returns how many rows it deleted" do
      assert_equal 1, query.where(done: true).delete!
    end

    it "raises the violation delete returns" do
      error = assert_raises(Skyward::ORM::ViolationError) do
        Skyward::ORM::Query.new(TablesFixtures::List, session).where(id: 1).delete!
      end
      restricted = violations.fetch(:foreign_key).fetch(0)

      assert_equal empty.violated(restricted, "DELETE FROM lists WHERE id = 1", :lists), error.violation
    end
  end
end
