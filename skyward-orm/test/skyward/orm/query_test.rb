# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Query do
  sqlite = Skyward::ORM::Adapters::SQLite
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  select = %(SELECT "id", "list_id", "title", "priority", "due_on", "done", "created_at" FROM "todos")

  # PostgreSQL numbers its placeholders, so this shows each one's position.
  numbered = Module.new do
    extend Skyward::ORM::Adapters::SQLite

    def self.placeholder(position) = "$#{position}"
  end

  let(:adapter) { sqlite }
  let(:connection) do
    sqlite.connect(":memory:").tap do |connection|
      connection.execute(
        "CREATE TABLE todos (id INTEGER PRIMARY KEY, list_id INTEGER, title TEXT, priority TEXT, due_on TEXT, " \
        "done INTEGER, created_at TEXT)"
      )
    end
  end
  let(:session) do
    Skyward::ORM::Connection::Session.new.tap do |session|
      session.connect(
        Skyward::ORM::Connection::Database.new(
          adapter,
          Skyward::ORM::Connection::Pool.new(1, -> { connection }),
          Skyward::ORM::Tables::ColumnTypes.new(reader),
          sqlite.tables(connection),
          check: false
        )
      )
    end
  end
  let(:query) { Skyward::ORM::Query.new(todo, session) }
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
      connection.execute(
        %(INSERT INTO "#{row.class.table_name}" VALUES (#{Array.new(row.to_h.size, "?").join(", ")})),
        row.to_h.values.map { |value| Skyward::ORM::Adapters::SQLite.encode(value) }
      )
    end
  end

  def traced
    # Connecting reads the schema, so that's done before tracing starts.
    session
    statements = []
    connection.trace { |sql| statements << sql }
    yield
    statements
  end

  describe "#initialize" do
    it "is frozen" do
      assert_predicate query, :frozen?
    end

    it "leaves the arrays it's given unfrozen" do
      conditions = [[:done, false]]
      Skyward::ORM::Query.new(todo, session, conditions:)

      refute_predicate conditions, :frozen?
    end
  end

  describe "#where" do
    it "returns a new frozen query" do
      assert_predicate query.where(done: false), :frozen?
    end

    it "leaves the query it started from as it was" do
      query.where(done: false)

      assert_equal [select, []], query.to_sql
    end

    it "matches a value with =, bound as the adapter encodes it" do
      assert_equal [%(#{select} WHERE "done" = ?), [0]], query.where(done: false).to_sql
    end

    it "matches nil with IS NULL" do
      assert_equal [%(#{select} WHERE "due_on" IS NULL), []], query.where(due_on: nil).to_sql
    end

    it "matches an array with IN" do
      assert_equal [%(#{select} WHERE "priority" IN (?, ?)), %w[high normal]],
                   query.where(priority: %i[high normal]).to_sql
    end

    it "matches nothing with an empty array, without IN ()" do
      assert_equal [%(#{select} WHERE 1 = 0), []], query.where(id: []).to_sql
    end

    it "returns no rows for an empty array" do
      insert(milk)

      assert_empty query.where(id: []).to_a
    end

    it "matches an array of only nil with IS NULL" do
      assert_equal [%(#{select} WHERE "due_on" IS NULL), []], query.where(due_on: [nil]).to_sql
    end

    it "matches an array holding nil with IN or IS NULL" do
      assert_equal [%(#{select} WHERE ("due_on" IN (?) OR "due_on" IS NULL)), ["2026-10-20"]],
                   query.where(due_on: [nil, eggs.due_on]).to_sql
    end

    it "returns the rows that are NULL and the rows in the array" do
      insert(milk, eggs)

      assert_equal [milk, eggs], query.where(due_on: [nil, eggs.due_on]).to_a
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "joins repeated wheres with AND, numbering placeholders across them" do
        expected = [%(#{select} WHERE "done" = $1 AND "priority" IN ($2, $3) AND "title" = $4),
                    [0, "high", "normal", "Buy milk"]]

        assert_equal expected, query.where(done: false, priority: %i[high normal]).where(title: "Buy milk").to_sql
      end
    end

    it "refuses a column the table doesn't have, suggesting the nearest" do
      error = assert_raises(ArgumentError) { query.where(dnoe: false) }

      assert_equal "TablesFixtures::Todo has no column dnoe. Did you mean done?", error.message
    end

    it "refuses a column with nothing to suggest" do
      error = assert_raises(ArgumentError) { query.where(zzzzzz: false) }

      assert_equal "TablesFixtures::Todo has no column zzzzzz.", error.message
    end
  end

  describe "#order" do
    it "orders by a column ascending, or in the direction given" do
      assert_equal [%(#{select} ORDER BY "title" ASC, "created_at" DESC), []],
                   query.order(:title, created_at: :desc).to_sql
    end

    it "appends to the order so far" do
      assert_equal [%(#{select} ORDER BY "done" DESC, "title" ASC), []], query.order(done: :desc).order(:title).to_sql
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) { query.order(titel: :desc) }

      assert_equal "TablesFixtures::Todo has no column titel. Did you mean title?", error.message
    end

    it "refuses a direction other than :asc or :desc" do
      error = assert_raises(ArgumentError) { query.order(title: :up) }

      assert_equal "TablesFixtures::Todo can't order title by :up, only :asc or :desc", error.message
    end
  end

  describe "#group" do
    it "groups by the columns, appending to the groups so far" do
      assert_equal [%(#{select} GROUP BY "list_id", "done"), []], query.group(:list_id).group(:done).to_sql
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) { query.group(:lsit_id) }

      assert_equal "TablesFixtures::Todo has no column lsit_id. Did you mean list_id?", error.message
    end
  end

  describe "#first" do
    it "returns the first row in the query's order" do
      insert(milk, eggs)

      assert_equal eggs, query.order(:title).first
    end

    it "runs with LIMIT 1" do
      insert(milk)

      assert_equal([%(#{select} ORDER BY "title" ASC LIMIT 1)], traced { query.order(:title).first })
    end

    it "orders by the primary key when nothing orders it" do
      tag = Class.new(Skyward::ORM::Record) do
        table :tags
        primary_key :name
        attr_reader :name, :colour
      end
      connection.execute("CREATE TABLE tags (name TEXT PRIMARY KEY, colour TEXT)")
      insert(tag.new(name: "work", colour: "blue"), tag.new(name: "home", colour: "green"))

      assert_equal tag.new(name: "home", colour: "green"), Skyward::ORM::Query.new(tag, session).first
    end

    it "is nil when no row matches" do
      assert_nil query.first
    end

    it "is the first n rows when given n" do
      insert(milk, eggs)

      assert_equal [eggs], query.order(:title).first(1)
    end
  end

  describe "#find_by" do
    it "is the first row matching the conditions" do
      insert(milk, eggs)

      assert_equal eggs, query.find_by(done: true)
    end
  end

  describe "#count" do
    it "counts the rows that match, with COUNT(*)" do
      insert(milk, eggs)

      assert_equal 1, query.where(done: false).count
    end

    it "leaves out the order, which PostgreSQL refuses beside COUNT(*)" do
      assert_equal(
        [%(SELECT COUNT(*) FROM "todos" WHERE "done" = 0)],
        traced { query.where(done: false).order(:title).count }
      )
    end

    it "counts the groups of a grouped query" do
      insert(milk, eggs, eggs.with(id: 3, title: "Buy bread"))

      assert_equal 2, query.group(:done).count
    end

    it "counts the rows the block accepts, in Ruby" do
      insert(milk, eggs)

      assert_equal 1, query.count(&:done)
    end

    it "counts the rows equal to an argument, in Ruby" do
      insert(milk, eggs)

      assert_equal 1, query.count(milk)
    end

    it "checks its table class before counting" do
      notes = Class.new(Skyward::ORM::Record) do
        table :notes
        attr_reader :id
      end
      checked = Skyward::ORM::Connection::Session.new.tap do |checking|
        checking.connect(
          Skyward::ORM::Connection::Database.new(
            adapter,
            Skyward::ORM::Connection::Pool.new(1, -> { connection }),
            Skyward::ORM::Tables::ColumnTypes.new(reader),
            sqlite.tables(connection),
            check: true
          )
        )
      end

      assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, checked).count }
    end
  end

  describe "#each" do
    it "yields each row" do
      insert(milk, eggs)

      assert_equal [milk, eggs], query.to_a
    end

    it "returns the query" do
      assert_same(query, query.each { |row| row })
    end

    it "returns an Enumerator without a block" do
      insert(milk)

      assert_equal [milk], query.each.to_a
    end

    it "runs the query again for each call" do
      insert(milk)
      query.to_a
      insert(eggs)

      assert_equal [milk, eggs], query.to_a
    end

    it "gives the query Enumerable's methods, so select filters in Ruby" do
      insert(milk, eggs)

      assert_equal [eggs], query.select(&:done)
    end
  end

  describe "#to_sql" do
    it "shows the SQL and its binds without running it" do
      assert_empty(traced { query.where(done: false).to_sql })
    end

    it "quotes every identifier, so a column named order, group or user can be queried" do
      reserved = Class.new(Skyward::ORM::Record) do
        table :user
        attr_reader :order, :group, :user
      end
      connection.execute(%(CREATE TABLE "user" ("order" INTEGER, "group" TEXT, "user" TEXT)))
      row = reserved.new(order: 1, group: "staff", user: "jake")
      insert(row, row.with(order: 2, user: "sam"))

      assert_equal [row],
                   Skyward::ORM::Query.new(reserved, session).where(user: "jake").order(:order).group(:group).to_a
    end

    it "escapes a double quote in a name by doubling it" do
      quoted = Class.new(Skyward::ORM::Record) do
        table :'to"dos'
        attr_reader :id
      end

      assert_equal [%(SELECT "id" FROM "to""dos"), []], Skyward::ORM::Query.new(quoted, session).to_sql
    end
  end
end
