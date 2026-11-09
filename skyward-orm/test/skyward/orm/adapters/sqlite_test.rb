# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "tmpdir"

describe Skyward::ORM::Adapters::SQLite do
  sqlite = Skyward::ORM::Adapters::SQLite
  catalog = Skyward::ORM::Catalog

  schema = <<~SQL
    CREATE TABLE lists (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL CONSTRAINT lists_name_key UNIQUE,
      slug TEXT
    );
    CREATE UNIQUE INDEX lists_slug_index ON lists (lower(slug));
    CREATE TABLE todos (
      id INTEGER PRIMARY KEY,
      list_id INTEGER NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE RESTRICT,
      title varchar(200) NOT NULL CONSTRAINT todos_title_check CHECK (length(title) > 0),
      done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0, 1)),
      code TEXT
    );
    CREATE UNIQUE INDEX todos_code_index ON todos (code);
    CREATE INDEX todos_list_id_done_index ON todos (list_id, done);
    INSERT INTO lists (id, name, slug) VALUES (1, 'Home', 'home');
    INSERT INTO todos (list_id, title, code) VALUES (1, 'Buy milk', 'milk');
  SQL

  let(:connection) { sqlite.connect(":memory:").tap { |connection| connection.execute_batch(schema) } }
  let(:tables) { sqlite.tables(connection) }

  def violation(sql, table, tables = self.tables)
    connection.execute(sql)
  rescue StandardError => e
    Skyward::ORM::Adapters::SQLite.violation(e, tables, table)
  end

  def violation_of(kind, constraint, columns, message)
    Skyward::ORM::Violation.new(kind:, constraint:, columns:, message:)
  end

  describe ".driver" do
    it "is the sqlite3 gem" do
      assert_equal "sqlite3", sqlite.driver
    end
  end

  describe ".connect" do
    it "waits on another connection's lock rather than failing at once" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "todos.db")
        holder = sqlite.connect(path)
        holder.execute("CREATE TABLE todos (title TEXT)")
        holder.execute("BEGIN IMMEDIATE")
        writer = Thread.new { sqlite.connect(path).execute("INSERT INTO todos VALUES ('Milk')") }
        Thread.pass while writer.status == "run"
        holder.execute("COMMIT")
        writer.join

        assert_equal [["Milk"]], holder.execute("SELECT title FROM todos")
      end
    end

    it "turns foreign keys on" do
      assert_equal [[1]], sqlite.connect(":memory:").execute("PRAGMA foreign_keys")
    end
  end

  describe ".pool_size" do
    it "keeps the size asked for" do
      assert_equal 5, sqlite.pool_size("todos.db", 5)
    end

    it "is one for :memory:, where each connection opens its own database" do
      assert_equal 1, sqlite.pool_size(":memory:", 5)
    end
  end

  describe ".require_version" do
    it "accepts SQLite 3.35, the first with RETURNING" do
      assert_nil sqlite.require_version("3.35.0")
    end

    it "refuses an older SQLite" do
      error = assert_raises(Skyward::Core::BootError) { sqlite.require_version("3.34.1") }

      assert_equal "Skyward ORM needs SQLite 3.35 or later, for RETURNING, but the sqlite3 gem loaded SQLite 3.34.1. " \
                   "Update the sqlite3 gem, or the SQLite it's built against.",
                   error.message
    end
  end

  describe ".placeholder" do
    it "is a question mark at every position" do
      assert_equal "?", sqlite.placeholder(2)
    end
  end

  describe ".sql_type" do
    it "maps each column type to the type a migration writes" do
      types = %i[integer float string bool date time enum].to_h { |type| [type, sqlite.sql_type(type)] }

      assert_equal(
        { integer: "INTEGER", float: "REAL", string: "TEXT", bool: "INTEGER", date: "TEXT", time: "TEXT",
          enum: "TEXT" },
        types
      )
    end

    it "has none for an untyped column" do
      assert_nil sqlite.sql_type(:untyped)
    end
  end

  describe ".identity" do
    it "has no clause, since an INTEGER PRIMARY KEY numbers its rows" do
      assert_nil sqlite.identity
    end
  end

  describe ".default_expression" do
    it "puts the expression in parentheses, which SQLite needs for anything but a literal" do
      connection = sqlite.connect(":memory:")
      connection.execute("CREATE TABLE stamps (at TEXT DEFAULT #{sqlite.default_expression("datetime('now')")})")
      connection.execute("INSERT INTO stamps DEFAULT VALUES")

      assert_match(/\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\z/, connection.execute("SELECT at FROM stamps").dig(0, 0))
    end
  end

  describe ".compatible?" do
    it "accepts any declared type for an untyped column" do
      assert sqlite.compatible?(:untyped, "BLOB")
    end

    it "accepts a declared type with the same affinity as the one a migration writes" do
      declared = [
        [:integer, "INTEGER"],
        [:integer, "bigint"],
        [:bool, "int"],
        [:float, "DOUBLE PRECISION"],
        [:float, "float"],
        [:string, "varchar(255)"],
        [:enum, "CLOB"],
        [:date, "text"]
      ]

      assert(declared.all? { |type, sql_type| sqlite.compatible?(type, sql_type) })
    end

    it "refuses a declared type with another affinity" do
      declared = [[:integer, "TEXT"], [:string, "BLOB"], [:string, ""], [:time, "DATETIME"], [:float, "NUMERIC"]]

      assert(declared.none? { |type, sql_type| sqlite.compatible?(type, sql_type) })
    end
  end

  describe ".encode" do
    it "stores true as 1" do
      assert_equal 1, sqlite.encode(true)
    end

    it "stores false as 0" do
      assert_equal 0, sqlite.encode(false)
    end

    it "stores a symbol as its name" do
      assert_equal "high", sqlite.encode(:high)
    end

    it "stores a time as fixed-width UTC text" do
      assert_equal "2026-10-18 09:30:00.000000", sqlite.encode(Time.new(2026, 10, 18, 19, 30, 0, "+10:00"))
    end

    it "keeps a time to the microsecond" do
      assert_equal "2026-10-18 09:30:00.123456",
                   sqlite.encode(Time.utc(2026, 10, 18, 9, 30, 123_456_789/1_000_000_000r))
    end

    it "stores a date as ISO 8601" do
      assert_equal "2026-10-18", sqlite.encode(Date.new(2026, 10, 18))
    end

    it "passes anything else through" do
      assert_equal "Milk", sqlite.encode("Milk")
    end
  end

  describe ".decode" do
    it "reads 1 as true" do
      assert sqlite.decode(:bool, 1)
    end

    it "reads 0 as false" do
      refute sqlite.decode(:bool, 0)
    end

    it "reads a date" do
      assert_equal Date.new(2026, 10, 18), sqlite.decode(:date, "2026-10-18")
    end

    it "reads a time back == to the one written, to the microsecond" do
      time = Time.new(2026, 10, 18, 19, 30, 123_456_789/1_000_000_000r, "+10:00")

      assert_equal time.floor(6), sqlite.decode(:time, sqlite.encode(time))
    end

    it "reads a time in UTC" do
      assert_predicate sqlite.decode(:time, "2026-10-18 09:30:00.000000"), :utc?
    end

    it "reads CURRENT_TIMESTAMP's format, which has no fraction" do
      assert_equal Time.utc(2026, 10, 18, 9, 30), sqlite.decode(:time, "2026-10-18 09:30:00")
    end

    it "reads a symbol" do
      assert_equal :high, sqlite.decode(:enum, "high")
    end

    it "passes an integer through" do
      assert_equal 42, sqlite.decode(:integer, 42)
    end

    it "passes a float through" do
      assert_in_delta 1.5, sqlite.decode(:float, 1.5)
    end

    it "freezes a string" do
      assert_predicate sqlite.decode(:string, +"Milk"), :frozen?
    end

    it "passes an untyped value through, frozen" do
      assert_predicate sqlite.decode(:untyped, +"Milk"), :frozen?
    end
  end

  describe ".tables" do
    def table(name) = tables.find { |table| table.name == name }

    it "reads each column's declared type and nullability, with a primary key never null" do
      expected = [
        catalog::Column.new(name: :id, type: "INTEGER", nullable: false),
        catalog::Column.new(name: :list_id, type: "INTEGER", nullable: false),
        catalog::Column.new(name: :title, type: "varchar(200)", nullable: false),
        catalog::Column.new(name: :done, type: "INTEGER", nullable: false),
        catalog::Column.new(name: :code, type: "TEXT", nullable: true)
      ]

      assert_equal expected, table(:todos).columns
    end

    it "reads each index, but not those its constraints make" do
      expected = [
        catalog::Index.new(name: "todos_code_index", columns: [:code], unique: true),
        catalog::Index.new(name: "todos_list_id_done_index", columns: %i[list_id done], unique: false)
      ]

      assert_equal expected, table(:todos).indexes
    end

    it "reads an index on an expression as having no columns" do
      assert_equal [catalog::Index.new(name: "lists_slug_index", columns: [], unique: true)], table(:lists).indexes
    end

    it "reads each constraint from the CREATE TABLE" do
      expected = [
        catalog::Constraint.new(name: nil, kind: :primary_key, columns: [:id], references: nil),
        catalog::Constraint.new(
          name: "todos_list_id_fkey",
          kind: :foreign_key,
          columns: [:list_id],
          references: :lists
        ),
        catalog::Constraint.new(name: "todos_title_check", kind: :check, columns: [:title], references: nil),
        catalog::Constraint.new(name: nil, kind: :check, columns: [:done], references: nil)
      ]

      assert_equal expected, table(:todos).constraints
    end

    it "leaves out SQLite's own tables, and reads a table with no indexes" do
      connection = sqlite.connect(":memory:")
      connection.execute("CREATE TABLE counters (id INTEGER PRIMARY KEY AUTOINCREMENT)")

      assert_equal([[:counters, []]], sqlite.tables(connection).map { |table| [table.name, table.indexes] })
    end
  end

  describe ".violation" do
    it "is nil for an error that isn't a constraint" do
      assert_nil violation("SELECT * FROM missing", :missing)
    end

    it "names a unique index on an expression, which has no columns" do
      assert_equal violation_of(:unique, "lists_slug_index", [], "UNIQUE constraint failed: index 'lists_slug_index'"),
                   violation("INSERT INTO lists (name, slug) VALUES ('Work', 'HOME')", :lists)
    end

    it "names a unique constraint, from its columns" do
      assert_equal violation_of(:unique, "lists_name_key", [:name], "UNIQUE constraint failed: lists.name"),
                   violation("INSERT INTO lists (name) VALUES ('Home')", :lists)
    end

    it "reads a duplicate primary key as unique" do
      assert_equal violation_of(:unique, nil, [:id], "UNIQUE constraint failed: lists.id"),
                   violation("INSERT INTO lists (id, name) VALUES (1, 'Work')", :lists)
    end

    it "names a unique index, from its columns" do
      assert_equal violation_of(:unique, "todos_code_index", [:code], "UNIQUE constraint failed: todos.code"),
                   violation("INSERT INTO todos (list_id, title, code) VALUES (1, 'Eggs', 'milk')", :todos)
    end

    it "leaves out what the schema it was given doesn't have" do
      assert_equal [
        violation_of(:unique, nil, [:name], "UNIQUE constraint failed: lists.name"),
        violation_of(:unique, "lists_slug_index", [], "UNIQUE constraint failed: index 'lists_slug_index'")
      ],
                   [
                     violation("INSERT INTO lists (name) VALUES ('Home')", :lists, []),
                     violation("INSERT INTO lists (name, slug) VALUES ('Work', 'HOME')", :lists, [])
                   ]
    end

    it "reads a not-null violation's column" do
      assert_equal violation_of(:not_null, nil, [:name], "NOT NULL constraint failed: lists.name"),
                   violation("INSERT INTO lists (name) VALUES (NULL)", :lists)
    end

    it "reads a check's columns from the schema" do
      assert_equal violation_of(:check, "todos_title_check", [:title], "CHECK constraint failed: todos_title_check"),
                   violation("INSERT INTO todos (list_id, title) VALUES (1, '')", :todos)
    end

    it "has no columns for a check with no name, which SQLite reports by its expression" do
      assert_equal violation_of(:check, "done IN (0, 1)", [], "CHECK constraint failed: done IN (0, 1)"),
                   violation("INSERT INTO todos (list_id, title, done) VALUES (1, 'Eggs', 2)", :todos)
    end

    it "reads a foreign key from the table written" do
      assert_equal violation_of(:foreign_key, "todos_list_id_fkey", [:list_id], "FOREIGN KEY constraint failed"),
                   violation("INSERT INTO todos (list_id, title) VALUES (9, 'Eggs')", :todos)
    end

    it "reads a RESTRICT foreign key that refers to the table written, which SQLite reports as a trigger's" do
      assert_equal violation_of(:foreign_key, "todos_list_id_fkey", [:list_id], "FOREIGN KEY constraint failed"),
                   violation("DELETE FROM lists", :lists)
    end

    it "can't say which foreign key failed when more than one could have" do
      connection.execute("CREATE TABLE shares (list_id INTEGER REFERENCES lists, todo_id INTEGER REFERENCES todos)")

      assert_equal violation_of(:foreign_key, nil, [], "FOREIGN KEY constraint failed"),
                   violation("INSERT INTO shares (list_id, todo_id) VALUES (9, 1)", :shares)
    end

    it "is nil for a constraint it doesn't report, such as a trigger's" do
      connection.execute("CREATE TRIGGER no_lists BEFORE INSERT ON lists BEGIN SELECT RAISE(ABORT, 'no'); END")

      assert_nil violation("INSERT INTO lists (name) VALUES ('Work')", :lists)
    end
  end
end
