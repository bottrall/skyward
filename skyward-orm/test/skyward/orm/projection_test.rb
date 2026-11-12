# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Projection do
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  list = TablesFixtures::List
  title = TablesFixtures::TodoTitle
  columns = %("id", "list_id", "title", "priority", "due_on", "done", "created_at")
  # The SQL beside each violation breaks it the same way, so the database
  # gives its message.
  unique = [
    Skyward::ORM::Violation.new(kind: :unique, constraint: "lists_name_key", columns: [:name], message: nil),
    "INSERT INTO lists VALUES (3, 'Home')", :lists
  ]
  check = [
    Skyward::ORM::Violation.new(kind: :check, constraint: "todos_title_check", columns: [:title], message: nil),
    "UPDATE todos SET title = '' WHERE id = 2", :todos
  ]
  restricted = [
    Skyward::ORM::Violation.new(
      kind: :foreign_key, constraint: "todos_list_id_fkey", columns: [:list_id], message: nil
    ),
    "DELETE FROM lists WHERE id = 1", :lists
  ]

  let(:empty) { TestDatabase.empty }
  let(:adapter) { empty.adapter }
  let(:connection) do
    integer, date, bool, time = %i[integer date bool time].map { |type| adapter.sql_type(TestDatabase.column(type)) }
    empty.connect.tap do |connection|
      connection.execute("CREATE TABLE lists (id #{integer} PRIMARY KEY, name TEXT CONSTRAINT lists_name_key UNIQUE)")
      connection.execute("INSERT INTO lists VALUES (1, 'Home'), (2, 'Work')")
      connection.execute(
        "CREATE TABLE todos (id #{integer} PRIMARY KEY, " \
        "list_id #{integer} CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE RESTRICT, " \
        "title TEXT NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200), " \
        "priority TEXT, due_on #{date}, done #{bool}, created_at #{time})"
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
          adapter.tables(connection),
          check: false
        )
      )
    end
  end
  let(:all) { Skyward::ORM::Query.new(todo, session, scope: :all) }
  let(:query) { Skyward::ORM::Query.new(todo, session) }
  let(:milk) do
    todo.new(
      id: 1,
      list_id: 1,
      title: "Buy milk",
      priority: :high,
      due_on: nil,
      done: false,
      created_at: Time.utc(2026, 10, 18, 9, 30)
    )
  end
  let(:eggs) { milk.with(id: 2, list_id: 2, title: "Buy eggs", priority: :normal, done: true) }

  def traced
    yield
    sent
  end

  def insert(*rows)
    rows.each do |row|
      placeholders = Array.new(row.to_h.size) { |index| adapter.placeholder(index + 1) }
      connection.execute(
        "INSERT INTO todos VALUES (#{placeholders.join(", ")})", row.to_h.values.map { |value| adapter.encode(value) }
      )
    end
  end

  describe "#insert" do
    it "inserts a row, and returns it as the table class, returning every column" do
      inserted = nil
      statements = traced { inserted = all.into(todo).insert(**milk.to_h) }
      shown = empty.shown(
        %(INSERT INTO "todos" (#{columns}) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING #{columns}), milk.to_h.values
      )

      assert_equal [[shown], milk], [statements, inserted]
    end

    it "returns the row as the row class, returning only its members" do
      inserted = nil
      statements = traced { inserted = all.into(title).insert(**milk.to_h) }

      assert_equal [title.new(id: 1, title: "Buy milk"), %(RETURNING "id", "title")],
                   [inserted, statements.dig(0, 0)[/RETURNING.*/]]
    end

    it "inserts through a query that's nothing but into, as through an explicit all" do
      assert_equal title.new(id: 1, title: "Buy milk"), query.into(title).insert(**milk.to_h)
    end

    it "checks its values as a table class's insert does" do
      error = assert_raises(ArgumentError) { all.into(title).insert(list_id: 1, title: "Buy milk", dnoe: true) }

      assert_equal "TablesFixtures::Todo has no column dnoe. Did you mean done?", error.message
    end

    it "refuses a query with conditions, before any SQL runs" do
      projected = query.where(id: 1).into(title)
      error = nil
      statements = traced { error = assert_raises(ArgumentError) { projected.insert(**milk.to_h) } }

      assert_equal ["TablesFixtures::Todo can't insert through a query with conditions. " \
                    "Start from TablesFixtures::Todo.into, with nothing else on it.", []],
                   [error.message, statements]
    end

    it "refuses a query merged with a narrowed one" do
      assert_equal "TablesFixtures::Todo can't insert through a query with conditions. " \
                   "Start from TablesFixtures::Todo.into, with nothing else on it.",
                   assert_raises(ArgumentError) { query.into(title).merge(query.exclude).insert(**milk.to_h) }.message
    end

    it "refuses an exclude, or a where given nothing, which leave no conditions but narrow the query" do
      errors = [all.exclude.into(title), all.where.into(title)].map do |projected|
        assert_raises(ArgumentError) { projected.insert(**milk.to_h) }.message
      end

      assert_equal ["TablesFixtures::Todo can't insert through a query with conditions. " \
                    "Start from TablesFixtures::Todo.into, with nothing else on it."] * 2,
                   errors
    end

    it "refuses into expressions, a join, order, group, limit or offset, naming each" do
      projected = all.join(list, list_id: :id).order(:id).group(:id).limit(1).offset(1)
                     .into(title, title: "upper(title)")
      error = assert_raises(ArgumentError) { projected.insert(**milk.to_h) }

      assert_equal "TablesFixtures::Todo can't insert through a query with into expressions, join, order, group, " \
                   "limit or offset. Start from TablesFixtures::Todo.into, with nothing else on it.",
                   error.message
    end

    it "refuses a left join" do
      error = assert_raises(ArgumentError) { all.left_join(list, list_id: :id).into(title).insert(**milk.to_h) }

      assert_equal "TablesFixtures::Todo can't insert through a query with join. " \
                   "Start from TablesFixtures::Todo.into, with nothing else on it.",
                   error.message
    end

    it "returns a violation, with the database's message" do
      lists = Skyward::ORM::Query.new(list, session, scope: :all).into(list)

      assert_equal empty.violated(*unique), lists.insert(id: 3, name: "Home")
    end
  end

  describe "#insert!" do
    it "returns the row it inserted" do
      assert_equal title.new(id: 1, title: "Buy milk"), all.into(title).insert!(**milk.to_h)
    end

    it "raises the violation insert returns" do
      lists = Skyward::ORM::Query.new(list, session, scope: :all).into(list)
      error = assert_raises(Skyward::ORM::ViolationError) { lists.insert!(id: 3, name: "Home") }

      assert_equal empty.violated(*unique), error.violation
    end
  end

  describe "#insert_all" do
    it "inserts the rows in one statement, and returns them as the table class, returning every column" do
      inserted = nil
      statements = traced { inserted = all.into(todo).insert_all([milk.to_h, eggs.to_h]) }
      shown = empty.shown(
        %(INSERT INTO "todos" (#{columns}) VALUES (?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?) RETURNING #{columns}),
        [*milk.to_h.values, *eggs.to_h.values]
      )

      assert_equal [[shown], [milk, eggs]], [statements, inserted.sort_by(&:id)]
    end

    it "returns the rows as the row class, returning only its members" do
      inserted = nil
      statements = traced { inserted = all.into(title).insert_all([milk.to_h, eggs.to_h]) }
      expected = [title.new(id: 1, title: "Buy milk"), title.new(id: 2, title: "Buy eggs")]

      assert_equal [expected, %(RETURNING "id", "title")], [inserted.sort_by(&:id), statements.dig(0, 0)[/RETURNING.*/]]
    end

    it "returns no rows for no rows, without touching the database" do
      inserted = nil
      statements = traced { inserted = query.into(title).insert_all([]) }

      assert_equal [[], []], [inserted, statements]
    end

    it "checks its rows as a table class's insert_all does" do
      error = assert_raises(ArgumentError) do
        all.into(title).insert_all([{ list_id: 1, title: "Buy milk", dnoe: true }])
      end

      assert_equal "TablesFixtures::Todo.insert_all row 0: TablesFixtures::Todo has no column dnoe. " \
                   "Did you mean done?",
                   error.message
    end

    it "refuses what insert refuses, even given no rows" do
      error = assert_raises(ArgumentError) { query.where(id: 1).into(title).insert_all([]) }

      assert_equal "TablesFixtures::Todo can't insert through a query with conditions. " \
                   "Start from TablesFixtures::Todo.into, with nothing else on it.",
                   error.message
    end

    it "returns a violation, with the database's message, inserting no row" do
      lists = Skyward::ORM::Query.new(list, session, scope: :all).into(list)

      assert_equal [empty.violated(*unique), 2],
                   [lists.insert_all([{ id: 4, name: "Away" }, { id: 3, name: "Home" }]), lists.count]
    end
  end

  describe "#insert_all!" do
    it "returns the rows it inserted" do
      assert_equal [title.new(id: 1, title: "Buy milk")], all.into(title).insert_all!([milk.to_h])
    end

    it "raises the violation insert_all returns" do
      lists = Skyward::ORM::Query.new(list, session, scope: :all).into(list)
      error = assert_raises(Skyward::ORM::ViolationError) { lists.insert_all!([{ id: 3, name: "Home" }]) }

      assert_equal empty.violated(*unique), error.violation
    end
  end

  describe "#update" do
    before { insert(milk, eggs) }

    it "returns the rows it changed as the table class, returning every column" do
      updated = nil
      statements = traced { updated = query.where(id: 2).into(todo).update(title: "Buy bread") }
      shown = empty.shown(%(UPDATE "todos" SET "title" = ? WHERE "id" = ? RETURNING #{columns}), ["Buy bread", 2])

      assert_equal [[shown], [eggs.with(title: "Buy bread")]], [statements, updated]
    end

    it "returns the rows as the row class, returning only its members" do
      updated = nil
      statements = traced { updated = query.where(id: 1).into(title).update(title: "Buy bread") }
      shown = empty.shown(%(UPDATE "todos" SET "title" = ? WHERE "id" = ? RETURNING "id", "title"), ["Buy bread", 1])

      assert_equal [[shown], [title.new(id: 1, title: "Buy bread")]], [statements, updated]
    end

    it "returns no rows when none match" do
      assert_empty query.where(id: 3).into(title).update(title: "Buy bread")
    end

    it "refuses what a query's update refuses" do
      error = assert_raises(ArgumentError) { query.into(title).update(done: true) }

      assert_equal "TablesFixtures::Todo can't update a query with no conditions, which would change every row. " \
                   "Narrow it with where or exclude, or start from TablesFixtures::Todo.all to change every row.",
                   error.message
    end

    it "refuses into expressions, which mean nothing portable in RETURNING" do
      error = assert_raises(ArgumentError) do
        query.where(id: 1).into(TablesFixtures::OpenCount, open: "count(*)").update(done: true)
      end

      assert_equal "TablesFixtures::Todo can't update a query with into expressions, " \
                   "which PostgreSQL and SQLite don't both support",
                   error.message
    end

    it "returns a violation, with the database's message" do
      assert_equal empty.violated(*check), query.where(id: 2).into(title).update(title: "")
    end
  end

  describe "#update!" do
    before { insert(milk, eggs) }

    it "returns the rows it changed" do
      assert_equal [title.new(id: 1, title: "Buy bread")], query.where(id: 1).into(title).update!(title: "Buy bread")
    end

    it "raises the violation update returns" do
      error = assert_raises(Skyward::ORM::ViolationError) { query.where(id: 2).into(title).update!(title: "") }

      assert_equal empty.violated(*check), error.violation
    end
  end

  describe "#delete" do
    before { insert(milk, eggs) }

    it "returns the rows it deleted as the table class, returning every column" do
      deleted = nil
      statements = traced { deleted = query.where(id: 2).into(todo).delete }
      shown = empty.shown(%(DELETE FROM "todos" WHERE "id" = ? RETURNING #{columns}), [2])

      assert_equal [[shown], [eggs]], [statements, deleted]
    end

    it "returns the rows as the row class, returning only its members" do
      assert_equal [title.new(id: 2, title: "Buy eggs")], query.where(done: true).into(title).delete
    end

    it "deletes every row of an explicit all, returning them" do
      assert_equal [title.new(id: 1, title: "Buy milk"), title.new(id: 2, title: "Buy eggs")],
                   all.into(title).delete.sort_by(&:id)
    end

    it "refuses every row of a query merged with an explicit all, which isn't one itself" do
      assert_match(/no conditions/, assert_raises(ArgumentError) { query.into(title).merge(all).delete }.message)
    end

    it "refuses what a query's delete refuses" do
      error = assert_raises(ArgumentError) { query.where(id: 1).limit(1).into(title).delete }

      assert_equal "TablesFixtures::Todo can't delete a query with limit, " \
                   "which PostgreSQL and SQLite don't both support",
                   error.message
    end

    it "returns a violation, with the database's message" do
      lists = Skyward::ORM::Query.new(list, session)

      assert_equal empty.violated(*restricted), lists.where(id: 1).into(list).delete
    end
  end

  describe "#delete!" do
    before { insert(milk, eggs) }

    it "returns the rows it deleted" do
      assert_equal [title.new(id: 2, title: "Buy eggs")], query.where(done: true).into(title).delete!
    end

    it "raises the violation delete returns" do
      lists = Skyward::ORM::Query.new(list, session)
      error = assert_raises(Skyward::ORM::ViolationError) { lists.where(id: 1).into(list).delete! }

      assert_equal empty.violated(*restricted), error.violation
    end
  end
end
