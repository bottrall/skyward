# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Query do
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
  )
  todo = TablesFixtures::Todo
  list = TablesFixtures::List
  with_list = TablesFixtures::TodoWithList
  select = %(SELECT "id", "list_id", "title", "priority", "due_on", "done", "created_at" FROM "todos")
  joined = %(SELECT "todos"."id", "todos"."list_id", "todos"."title", "todos"."priority", "todos"."due_on", ) +
           %("todos"."done", "todos"."created_at" FROM "todos" JOIN "lists" ON "todos"."list_id" = "lists"."id")

  recording = Data.define(:connection, :sent) do
    def execute(sql, binds = [])
      sent << [sql, binds]
      connection.execute(sql, binds)
    end
  end

  let(:empty) { TestDatabase.empty }
  let(:adapter) { empty.adapter }
  # Numbered as PostgreSQL's are, so each one's position shows on every database.
  let(:numbered) do
    numbering = empty.adapter
    Module.new do
      extend numbering

      def self.placeholder(position) = "$#{position}"
    end
  end
  # Taking an OFFSET with no LIMIT before it, as PostgreSQL does, on every database.
  let(:offset_alone) do
    offsetting = empty.adapter
    Module.new do
      extend offsetting

      def self.unlimited = nil
    end
  end
  let(:check) { false }
  let(:connection) do
    types = empty.adapter
    columns = Skyward::ORM::Tables::ColumnTypes.new(reader).columns(todo).map do |column|
      "#{column.name} #{types.sql_type(column.type)}"
    end
    empty.connect.tap do |connection|
      connection.execute("CREATE TABLE todos (#{columns.join(", ")}, PRIMARY KEY (id))")
      connection.execute(
        "CREATE TABLE lists (id #{types.sql_type(:integer)} PRIMARY KEY, name #{types.sql_type(:string)} NOT NULL)"
      )
    end
  end
  let(:sent) { [] }
  let(:session) do
    Skyward::ORM::Connection::Session.new.tap do |session|
      session.connect(
        Skyward::ORM::Connection::Database.new(
          adapter,
          Skyward::ORM::Connection::Pool.new(1, -> { recording.new(connection:, sent:) }),
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
  let(:home) { list.new(id: 1, name: "Home") }

  def insert(*rows)
    rows.each do |row|
      placeholders = Array.new(row.to_h.size) { |index| adapter.placeholder(index + 1) }
      connection.execute(
        %(INSERT INTO "#{row.class.table_name}" VALUES (#{placeholders.join(", ")})),
        row.to_h.values.map { |value| adapter.encode(value) }
      )
    end
  end

  # The SQL and binds a query shows on this database: each ? as the adapter's
  # placeholder, and each value as the adapter encodes it.
  def shown(sql, values)
    numbered = sql.gsub("?").with_index(1) { |_, position| adapter.placeholder(position) }
    [numbered, values.map { |value| adapter.encode(value) }]
  end

  def traced
    yield
    sent
  end

  describe "#initialize" do
    it "is frozen" do
      assert_predicate query, :frozen?
    end

    it "leaves the arrays it's given unfrozen" do
      conditions = [Skyward::ORM::Query::Comparison.new(column: :done, operator: "=", value: false)]
      Skyward::ORM::Query.new(todo, session, conditions:)

      refute_predicate conditions, :frozen?
    end
  end

  describe "#join" do
    it "returns a new frozen query, leaving the one it started from as it was" do
      assert_equal [true, [select, []]], [query.join(list, list_id: :id).frozen?, query.to_sql]
    end

    it "joins on the starting table's column equalling the joined table's, qualifying every column" do
      assert_equal [joined, []], query.join(list, list_id: :id).to_sql
    end

    it "joins on each pair, with AND" do
      assert_equal [%(#{joined} AND "todos"."title" = "lists"."name"), []],
                   query.join(list, list_id: :id, title: :name).to_sql
    end

    it "selects the README's TodoWithList, reading the joined table's column through its expression" do
      insert(home, milk.with(list_id: 1), eggs)
      rows = query.join(list, list_id: :id).into(with_list, list_name: "lists.name")
      expected = [
        [%(SELECT "todos"."id", "todos"."title", lists.name AS "list_name" FROM "todos" ) +
          %(JOIN "lists" ON "todos"."list_id" = "lists"."id"), []],
        [with_list.new(id: 1, title: "Buy milk", list_name: "Home")]
      ]

      assert_equal expected, [rows.to_sql, rows.to_a]
    end

    it "returns rows of the starting table, one for each row it matches" do
      insert(list.new(id: 1, name: "Buy milk"), list.new(id: 2, name: "Buy milk"), milk, eggs)

      assert_equal [milk, milk], query.join(list, title: :name).to_a
    end

    it "qualifies where's columns with the starting table" do
      sql = %(#{joined} WHERE "todos"."done" = ? AND ("todos"."due_on" IN (?) OR "todos"."due_on" IS NULL))

      assert_equal shown(sql, [false, eggs.due_on]),
                   query.join(list, list_id: :id).where(done: false, due_on: [nil, eggs.due_on]).to_sql
    end

    it "qualifies the column whose NULL rows exclude keeps" do
      assert_equal shown(%(#{joined} WHERE (NOT ("todos"."due_on" = ?) OR "todos"."due_on" IS NULL)), [eggs.due_on]),
                   query.join(list, list_id: :id).exclude(due_on: eggs.due_on).to_sql
    end

    it "qualifies the columns or groups" do
      sql = %(#{joined} WHERE ("todos"."done" = ? AND "todos"."list_id" = ?) OR "todos"."priority" = ?)

      assert_equal shown(sql, [false, 3, "high"]),
                   query.join(list, list_id: :id).where(done: false, list_id: 3).or(priority: :high).to_sql
    end

    it "qualifies group's and order's columns" do
      assert_equal [%(#{joined} GROUP BY "todos"."list_id" ORDER BY "todos"."title" ASC), []],
                   query.join(list, list_id: :id).group(:list_id).order(:title).to_sql
    end

    it "matches the joined table's columns with SQL" do
      work = eggs.with(list_id: 2)
      insert(home, list.new(id: 2, name: "Work"), milk.with(list_id: 1), work)

      assert_equal [work], query.join(list, list_id: :id).where("lists.name = ?", "Work").to_a
    end

    it "gives first the starting table's primary key to order by, which the joined table has too" do
      first = milk.with(list_id: 1)
      insert(home, eggs.with(list_id: 1), first)

      assert_equal first, query.join(list, list_id: :id).first
    end

    it "counts the rows it matches, through a subquery when they're limited" do
      insert(home, milk.with(list_id: 1), eggs)
      joining = query.join(list, list_id: :id)

      assert_equal [1, 1], [joining.count, joining.limit(5).count]
    end

    it "has no row when nothing matches" do
      insert(home, milk)

      refute_predicate query.join(list, list_id: :id), :exists?
    end

    it "refuses something that isn't a class" do
      error = assert_raises(ArgumentError) { query.join(:lists, list_id: :id) }

      assert_equal "TablesFixtures::Todo can't join :lists, which isn't a table class", error.message
    end

    it "refuses a class that isn't a Record" do
      error = assert_raises(ArgumentError) { query.join(String, id: :id) }

      assert_equal "TablesFixtures::Todo can't join String, which isn't a table class", error.message
    end

    it "refuses a Record with no table" do
      error = assert_raises(ArgumentError) { query.join(TablesFixtures::Typed, id: :integer) }

      assert_equal "TablesFixtures::Todo can't join TablesFixtures::Typed, which isn't a table class", error.message
    end

    it "refuses the table it started from" do
      error = assert_raises(ArgumentError) { query.join(todo, id: :id) }

      assert_equal "TablesFixtures::Todo can't join TablesFixtures::Todo, since todos is already in the query",
                   error.message
    end

    it "refuses a table it already joins" do
      error = assert_raises(ArgumentError) { query.join(list, list_id: :id).left_join(list, list_id: :id) }

      assert_equal "TablesFixtures::Todo can't join TablesFixtures::List, since lists is already in the query",
                   error.message
    end

    it "refuses nothing to join on" do
      error = assert_raises(ArgumentError) { query.join(list) }

      assert_equal "TablesFixtures::Todo can't join TablesFixtures::List on nothing. Give it columns, such as " \
                   "list_id: :id",
                   error.message
    end

    it "refuses a column the starting table doesn't have" do
      error = assert_raises(ArgumentError) { query.join(list, lsit_id: :id) }

      assert_equal "TablesFixtures::Todo has no column lsit_id. Did you mean list_id?", error.message
    end

    it "refuses a column the joined table doesn't have" do
      error = assert_raises(ArgumentError) { query.join(list, list_id: :nmae) }

      assert_equal "TablesFixtures::List has no column nmae. Did you mean name?", error.message
    end
  end

  describe "#left_join" do
    it "joins with LEFT JOIN" do
      assert_equal [joined.sub("JOIN", "LEFT JOIN"), []], query.left_join(list, list_id: :id).to_sql
    end

    it "fills a member from the joined table with nil when no row matches" do
      insert(home, milk.with(list_id: 1), eggs)
      expected = [
        with_list.new(id: 1, title: "Buy milk", list_name: "Home"),
        with_list.new(id: 2, title: "Buy eggs", list_name: nil)
      ]

      assert_equal expected,
                   query.left_join(list, list_id: :id).order(:id).into(with_list, list_name: "lists.name").to_a
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
      assert_equal shown(%(#{select} WHERE "done" = ?), [false]), query.where(done: false).to_sql
    end

    it "matches nil with IS NULL" do
      assert_equal [%(#{select} WHERE "due_on" IS NULL), []], query.where(due_on: nil).to_sql
    end

    it "matches an array with IN" do
      assert_equal shown(%(#{select} WHERE "priority" IN (?, ?)), %w[high normal]),
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
      assert_equal shown(%(#{select} WHERE ("due_on" IN (?) OR "due_on" IS NULL)), [eggs.due_on]),
                   query.where(due_on: [nil, eggs.due_on]).to_sql
    end

    it "returns the rows that are NULL and the rows in the array" do
      insert(milk, eggs)

      assert_equal [milk, eggs], query.where(due_on: [nil, eggs.due_on]).to_a
    end

    describe "with a range" do
      today = Date.new(2026, 10, 18)
      later = Date.new(2026, 10, 25)

      it "matches a..b with >= and <=" do
        assert_equal shown(%(#{select} WHERE "due_on" >= ? AND "due_on" <= ?), [today, later]),
                     query.where(due_on: today..later).to_sql
      end

      it "matches a...b with >= and <" do
        assert_equal shown(%(#{select} WHERE "due_on" >= ? AND "due_on" < ?), [today, later]),
                     query.where(due_on: today...later).to_sql
      end

      it "matches ..b with <=" do
        assert_equal shown(%(#{select} WHERE "due_on" <= ?), [today]), query.where(due_on: ..today).to_sql
      end

      it "matches ...b with <" do
        assert_equal shown(%(#{select} WHERE "due_on" < ?), [today]), query.where(due_on: ...today).to_sql
      end

      it "matches a.. with >=" do
        assert_equal shown(%(#{select} WHERE "due_on" >= ?), [today]), query.where(due_on: today..).to_sql
      end

      it "returns the rows in the range" do
        insert(milk, eggs, eggs.with(id: 3, due_on: later))

        assert_equal [eggs], query.where(due_on: today...later).to_a
      end

      it "refuses an end its column's type doesn't take" do
        error = assert_raises(ArgumentError) { query.where(due_on: "2026-10-25"..) }

        assert_equal %(TablesFixtures::Todo.due_on is Date?, not "2026-10-25" (String)), error.message
      end

      it "refuses a range with neither end" do
        error = assert_raises(ArgumentError) { query.where(due_on: nil..nil) }

        assert_equal "TablesFixtures::Todo can't match due_on to nil..nil, a range with neither end", error.message
      end
    end

    describe "with SQL" do
      it "adds the SQL in parentheses, binding its values as the adapter encodes them" do
        assert_equal shown(%(#{select} WHERE (title LIKE ? AND done = ?)), ["%milk%", false]),
                     query.where("title LIKE ? AND done = ?", "%milk%", false).to_sql
      end

      it "returns the rows the SQL matches" do
        insert(milk, eggs)

        assert_equal [milk], query.where("title LIKE ?", "%milk%").to_a
      end

      it "leaves a ? in a string as it is" do
        assert_equal [%(#{select} WHERE (title <> 'why?' AND id = #{adapter.placeholder(1)})), [1]],
                     query.where("title <> 'why?' AND id = ?", 1).to_sql
      end

      it "puts the closing parenthesis after a -- comment on a line of its own" do
        insert(milk, eggs)

        assert_equal [milk], query.where("title = ? -- exact", "Buy milk").where(done: false).to_a
      end

      it "refuses an Array value, which the driver would spread across several ?" do
        error = assert_raises(ArgumentError) { query.where("id IN (?) AND title = ?", [1, 2], "Buy milk").to_sql }

        assert_equal "An SQL condition binds one value to each ?, but value 1 is an Array", error.message
      end
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "joins repeated wheres with AND, numbering placeholders across them" do
        expected = [%(#{select} WHERE "done" = $1 AND "priority" IN ($2, $3) AND "title" = $4),
                    [adapter.encode(false), "high", "normal", "Buy milk"]]

        assert_equal expected, query.where(done: false, priority: %i[high normal]).where(title: "Buy milk").to_sql
      end

      it "numbers an SQL string's placeholders on from the query's other binds" do
        assert_equal [%(#{select} WHERE "done" = $1 AND (title = $2 OR title = $3)),
                      [adapter.encode(false), "Buy milk", "Buy eggs"]],
                     query.where(done: false).where("title = ? OR title = ?", "Buy milk", "Buy eggs").to_sql
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

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) { query.where(done: "yes") }

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end
  end

  describe "#exclude" do
    it "negates the conditions with NOT" do
      assert_equal shown(%(#{select} WHERE NOT ("done" = ?)), [true]), query.exclude(done: true).to_sql
    end

    it "negates IS NULL, leaving out only the NULL rows" do
      assert_equal [%(#{select} WHERE NOT ("due_on" IS NULL)), []], query.exclude(due_on: nil).to_sql
    end

    it "negates several conditions together, joined with AND to the conditions before it" do
      assert_equal shown(%(#{select} WHERE "list_id" = ? AND NOT ("done" = ? AND "priority" = ?)), [3, true, "high"]),
                   query.where(list_id: 3).exclude(done: true, priority: :high).to_sql
    end

    it "keeps the NULL rows of a nullable column" do
      assert_equal shown(%(#{select} WHERE (NOT ("due_on" = ?) OR "due_on" IS NULL)), [eggs.due_on]),
                   query.exclude(due_on: eggs.due_on).to_sql
    end

    it "keeps the NULL rows of a nullable column matched with an array" do
      assert_equal shown(%(#{select} WHERE (NOT ("due_on" IN (?)) OR "due_on" IS NULL)), [eggs.due_on]),
                   query.exclude(due_on: [eggs.due_on]).to_sql
    end

    it "keeps the NULL rows of a nullable column matched with a range, once" do
      assert_equal shown(
        %(#{select} WHERE (NOT ("due_on" >= ? AND "due_on" < ?) OR "due_on" IS NULL)),
        [eggs.due_on, Date.new(2026, 10, 25)]
      ),
                   query.exclude(due_on: eggs.due_on...Date.new(2026, 10, 25)).to_sql
    end

    it "keeps the NULL rows of an untyped column" do
      memos = Class.new(Skyward::ORM::Record) do
        table :memos
        attr_reader :id, :body
      end

      assert_equal shown(%(SELECT "id", "body" FROM "memos" WHERE (NOT ("body" = ?) OR "body" IS NULL)), ["a"]),
                   Skyward::ORM::Query.new(memos, session).exclude(body: "a").to_sql
    end

    it "returns the rows that don't match, including those whose column is NULL" do
      later = eggs.with(id: 3, due_on: Date.new(2026, 10, 25))
      insert(milk, eggs, later)

      assert_equal [milk, later], query.exclude(due_on: eggs.due_on, done: true).to_a
    end

    it "leaves out the NULL rows when the array holds nil" do
      later = eggs.with(id: 3, due_on: Date.new(2026, 10, 25))
      insert(milk, eggs, later)

      assert_equal [later], query.exclude(due_on: [nil, eggs.due_on]).to_a
    end

    it "negates SQL as it is, since its columns can't be known" do
      assert_equal shown(%(#{select} WHERE NOT ((title LIKE ?))), ["%milk%"]),
                   query.exclude("title LIKE ?", "%milk%").to_sql
    end

    it "returns the query as it is when there is nothing to exclude" do
      assert_equal shown(%(#{select} WHERE "done" = ?), [true]), query.where(done: true).exclude.to_sql
    end

    it "refuses a column the table doesn't have" do
      error = assert_raises(ArgumentError) { query.exclude(dnoe: true) }

      assert_equal "TablesFixtures::Todo has no column dnoe. Did you mean done?", error.message
    end

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) { query.exclude(done: "yes") }

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end
  end

  describe "#or" do
    it "matches the conditions before it, or the ones it's given" do
      assert_equal shown(%(#{select} WHERE "done" = ? OR "priority" = ?), [false, "high"]),
                   query.where(done: false).or(priority: :high).to_sql
    end

    it "groups several conditions on either side in parentheses" do
      due = Date.new(2026, 10, 18)..Date.new(2026, 10, 25)

      assert_equal shown(
        %(#{select} WHERE ("done" = ? AND "list_id" = ?) OR ("due_on" >= ? AND "due_on" <= ?)),
        [false, 3, Date.new(2026, 10, 18), Date.new(2026, 10, 25)]
      ),
                   query.where(done: false, list_id: 3).or(due_on: due).to_sql
    end

    it "is grouped in parentheses by a later where" do
      assert_equal shown(
        %(#{select} WHERE (("done" = ? AND "list_id" = ?) OR "priority" = ?) AND "title" = ?),
        [false, 3, "high", "Buy milk"]
      ),
                   query.where(done: false).where(list_id: 3).or(priority: :high).where(title: "Buy milk").to_sql
    end

    it "chains without parentheses" do
      assert_equal shown(%(#{select} WHERE "done" = ? OR "priority" = ? OR "list_id" = ?), [false, "high", 3]),
                   query.where(done: false).or(priority: :high).or(list_id: 3).to_sql
    end

    it "takes SQL" do
      assert_equal shown(%(#{select} WHERE "done" = ? OR (title LIKE ?)), [false, "%milk%"]),
                   query.where(done: false).or("title LIKE ?", "%milk%").to_sql
    end

    it "returns the rows that match either" do
      insert(milk, eggs, eggs.with(id: 3, title: "Buy bread", priority: :low))

      assert_equal [milk, eggs], query.where(done: false).or(priority: :normal).to_a
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "numbers placeholders across both sides" do
        assert_equal [%(#{select} WHERE ("done" = $1 OR (title = $2)) AND "list_id" = $3),
                      [adapter.encode(false), "Buy milk", 3]],
                     query.where(done: false).or("title = ?", "Buy milk").where(list_id: 3).to_sql
      end
    end

    it "refuses a query with no conditions to or with" do
      error = assert_raises(ArgumentError) { query.or(done: true) }

      assert_equal "TablesFixtures::Todo has no conditions to or with. Start with where or exclude.", error.message
    end

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) { query.where(done: true).or(done: "yes") }

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end

    it "refuses nothing to or with" do
      error = assert_raises(ArgumentError) { query.where(done: true).or }

      assert_equal "TablesFixtures::Todo has nothing to or with. Give or conditions or SQL.", error.message
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

  describe "#limit" do
    it "limits the rows with LIMIT, bound as a parameter" do
      assert_equal shown(%(#{select} LIMIT ?), [20]), query.limit(20).to_sql
    end

    it "returns at most that many rows" do
      insert(milk, eggs)

      assert_equal [milk], query.order(:id).limit(1).to_a
    end

    it "replaces an earlier limit" do
      assert_equal shown(%(#{select} LIMIT ?), [20]), query.limit(5).limit(20).to_sql
    end

    it "refuses a negative count" do
      error = assert_raises(ArgumentError) { query.limit(-1) }

      assert_equal "TablesFixtures::Todo can't limit by -1, only by a non-negative Integer", error.message
    end

    it "refuses anything but an Integer" do
      error = assert_raises(ArgumentError) { query.limit(2.5) }

      assert_equal "TablesFixtures::Todo can't limit by 2.5, only by a non-negative Integer", error.message
    end
  end

  describe "#offset" do
    it "skips rows with OFFSET, bound as a parameter after the adapter's clause for no limit" do
      assert_equal shown([select, adapter.unlimited, "OFFSET ?"].compact.join(" "), [40]), query.offset(40).to_sql
    end

    it "returns the rows after those it skips" do
      insert(milk, eggs)

      assert_equal [eggs], query.order(:id).offset(1).to_a
    end

    describe "with an adapter that takes an OFFSET alone" do
      let(:adapter) { offset_alone }

      it "has no LIMIT before it" do
        assert_equal shown(%(#{select} OFFSET ?), [40]), query.offset(40).to_sql
      end
    end

    describe "with numbered placeholders" do
      let(:adapter) { numbered }

      it "follows the limit, numbering both after the conditions" do
        assert_equal [%(#{select} WHERE "done" = $1 ORDER BY "id" ASC LIMIT $2 OFFSET $3),
                      [adapter.encode(false), 20, 40]],
                     query.where(done: false).order(:id).limit(20).offset(40).to_sql
      end
    end

    it "gives every page of a query the same SQL" do
      page = query.order(:id).limit(20)

      assert_equal page.offset(0).to_sql.first, page.offset(40).to_sql.first
    end

    it "returns the page asked for" do
      insert(*(1..7).map { |id| milk.with(id:) })

      assert_equal [5, 6], query.order(:id).limit(2).offset(4).map(&:id)
    end

    it "replaces an earlier offset" do
      assert_equal shown([select, adapter.unlimited, "OFFSET ?"].compact.join(" "), [40]),
                   query.offset(20).offset(40).to_sql
    end

    it "refuses a negative count" do
      error = assert_raises(ArgumentError) { query.offset(-1) }

      assert_equal "TablesFixtures::Todo can't offset by -1, only by a non-negative Integer", error.message
    end
  end

  describe "#into" do
    title = TablesFixtures::TodoTitle
    open_count = TablesFixtures::OpenCount

    it "returns a new frozen query, leaving the one it started from as it was" do
      assert_equal [true, [select, []]], [query.into(title).frozen?, query.to_sql]
    end

    it "selects the README's TodoTitle from the same-named columns" do
      insert(milk, eggs)
      titles = query.where(done: false).into(title)
      expected = [shown(%(SELECT "id", "title" FROM "todos" WHERE "done" = ?), [false]),
                  [title.new(id: 1, title: "Buy milk")]]

      assert_equal expected, [titles.to_sql, titles.to_a]
    end

    it "selects the README's OpenCount, with an expression AS its member" do
      insert(milk.with(list_id: 1), eggs.with(list_id: 1), milk.with(id: 3, list_id: 2), milk.with(id: 4, list_id: 2))
      counts = query.where(done: false).group(:list_id).into(open_count, open: "count(*)")
      # OpenCount is untyped, so each count is as the driver returns it.
      one, two = connection.execute("SELECT 1, 2").fetch(0)
      expected = [
        shown(%(SELECT "list_id", count(*) AS "open" FROM "todos" WHERE "done" = ? GROUP BY "list_id"), [false]),
        [open_count.new(list_id: 1, open: one), open_count.new(list_id: 2, open: two)]
      ]

      assert_equal expected, [counts.to_sql, counts.sort_by(&:list_id)]
    end

    it "keeps the clauses before it, and takes more after it" do
      projected = query.where(done: false).order(:id).limit(20).offset(40).into(title)
                       .where(title: "Buy milk").order(created_at: :desc)
      expected = shown(
        %(SELECT "id", "title" FROM "todos" WHERE "done" = ? AND "title" = ? ORDER BY "id" ASC, "created_at" DESC ) \
        "LIMIT ? OFFSET ?",
        [false, "Buy milk", 20, 40]
      )

      assert_equal expected, projected.to_sql
    end

    it "replaces the projection when called again" do
      assert_equal [%(SELECT "id", "title" FROM "todos"), []],
                   query.into(open_count, open: "count(*)").into(title).to_sql
    end

    it "leaves where, order and group naming the table's columns, not the row class's members" do
      counts = query.into(open_count, open: "count(*)")
      errors = [-> { counts.where(open: 1) }, -> { counts.order(:open) }, -> { counts.group(:open) }].map do |call|
        assert_raises(ArgumentError, &call).message
      end

      assert_equal ["TablesFixtures::Todo has no column open."] * 3, errors
    end

    it "leaves where checking its values against the table's column types" do
      error = assert_raises(ArgumentError) { query.into(title).where(done: "yes") }

      assert_equal %(TablesFixtures::Todo.done is bool, not "yes" (String)), error.message
    end

    it "decodes an expressed member as the expression, not as the column it's named like" do
      insert(milk.with(list_id: 1), milk.with(id: 3, list_id: 1))
      summary = Data.define(:done)
      count = connection.execute("SELECT count(*) FROM todos").dig(0, 0)

      assert_equal [summary.new(done: count)],
                   query.where(done: false).group(:list_id).into(summary, done: "count(*)").to_a
    end

    it "refuses an expression for a name that isn't a member" do
      error = assert_raises(ArgumentError) { query.into(title, total: "count(*)") }

      assert_equal "TablesFixtures::TodoTitle has no member total to take an expression", error.message
    end

    it "refuses a member that's neither a column nor given an expression" do
      error = assert_raises(ArgumentError) { query.into(open_count) }

      assert_equal "TablesFixtures::Todo has no column open, so TablesFixtures::OpenCount needs an expression for it",
                   error.message
    end
  end

  describe "#first" do
    it "returns the first row in the query's order" do
      insert(milk, eggs)

      assert_equal eggs, query.order(:title).first
    end

    it "runs with LIMIT 1" do
      insert(milk)

      assert_equal([shown(%(#{select} ORDER BY "title" ASC LIMIT ?), [1])], traced { query.order(:title).first })
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

    it "keeps the offset, with a limit of 1 in place of the query's" do
      assert_equal(
        [shown(%(#{select} ORDER BY "id" ASC LIMIT ? OFFSET ?), [1, 1])],
        traced { query.order(:id).limit(5).offset(1).first }
      )
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

    it "refuses a value its column's type doesn't take" do
      error = assert_raises(ArgumentError) { query.find_by(priority: :urgent) }

      assert_equal "TablesFixtures::Todo.priority is :low | :normal | :high, not :urgent (Symbol)", error.message
    end
  end

  describe "#count" do
    it "counts the rows that match, with COUNT(*)" do
      insert(milk, eggs)

      assert_equal 1, query.where(done: false).count
    end

    it "leaves out the order, which PostgreSQL refuses beside COUNT(*)" do
      assert_equal(
        [shown(%(SELECT COUNT(*) FROM "todos" WHERE "done" = ?), [false])],
        traced { query.where(done: false).order(:title).count }
      )
    end

    it "counts the groups of a grouped query" do
      insert(milk, eggs, eggs.with(id: 3, title: "Buy bread"))

      assert_equal 2, query.group(:done).count
    end

    it "counts a page through a subquery, without the order" do
      assert_equal(
        [shown(%(SELECT COUNT(*) FROM (SELECT 1 FROM "todos" LIMIT ? OFFSET ?) AS "counted"), [2, 1])],
        traced { query.order(:title).limit(2).offset(1).count }
      )
    end

    it "counts only the rows a limit leaves" do
      insert(milk, eggs, eggs.with(id: 3, title: "Buy bread"))

      assert_equal 2, query.limit(2).count
    end

    it "counts only the rows an offset leaves" do
      insert(milk, eggs, eggs.with(id: 3, title: "Buy bread"))

      assert_equal 1, query.offset(2).count
    end

    it "counts the rows the block accepts, in Ruby" do
      insert(milk, eggs)

      assert_equal 1, query.count(&:done)
    end

    it "counts the rows equal to an argument, in Ruby" do
      insert(milk, eggs)

      assert_equal 1, query.count(milk)
    end

    describe "with the check on" do
      let(:check) { true }

      it "checks its table class before counting" do
        assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, session).count }
      end

      it "checks each table class it joins before counting" do
        error = assert_raises(Skyward::ORM::SchemaMismatch) do
          Skyward::ORM::Query.new(list, session).join(notes, id: :id).count
        end

        assert_includes error.message, "The database has no table notes."
      end
    end
  end

  describe "#exists?" do
    it "is true when a row matches" do
      insert(milk)

      assert_predicate query.where(done: false), :exists?
    end

    it "is false when no row matches" do
      insert(milk)

      refute_predicate query.where(done: true), :exists?
    end

    it "selects 1 with LIMIT 1, keeping the offset but not the order" do
      assert_equal(
        [shown(%(SELECT 1 FROM "todos" WHERE "done" = ? LIMIT ? OFFSET ?), [false, 1, 1])],
        traced { query.where(done: false).order(:title).limit(5).offset(1).exists? }
      )
    end

    it "is false past the last row" do
      insert(milk)

      refute_predicate query.offset(1), :exists?
    end

    it "is false for a limit of 0" do
      insert(milk)

      refute_predicate query.limit(0), :exists?
    end

    describe "with the check on" do
      let(:check) { true }

      it "checks its table class before running the query" do
        assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, session).exists? }
      end

      it "checks each table class it joins before running the query" do
        error = assert_raises(Skyward::ORM::SchemaMismatch) do
          Skyward::ORM::Query.new(list, session).join(notes, id: :id).exists?
        end

        assert_includes error.message, "The database has no table notes."
      end
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

    describe "with the check on" do
      let(:check) { true }

      it "checks its table class before running the query" do
        assert_raises(Skyward::ORM::SchemaMismatch) { Skyward::ORM::Query.new(notes, session).to_a }
      end

      it "checks each table class it joins before running the query" do
        error = assert_raises(Skyward::ORM::SchemaMismatch) do
          Skyward::ORM::Query.new(list, session).join(notes, id: :id).to_a
        end

        assert_includes error.message, "The database has no table notes."
      end
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
      connection.execute(%(CREATE TABLE "user" ("order" TEXT, "group" TEXT, "user" TEXT)))
      row = reserved.new(order: "1", group: "staff", user: "jake")
      insert(row, row.with(order: "2", user: "sam"))

      assert_equal [row],
                   Skyward::ORM::Query.new(reserved, session).where(user: "jake").order(:order)
                                      .group(:order, :group, :user).to_a
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
