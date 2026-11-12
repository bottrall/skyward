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

  describe ".adapter_name" do
    it "is :sqlite" do
      assert_equal :sqlite, sqlite.adapter_name
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

  describe ".bind_limit" do
    it "is SQLite's default most variables" do
      assert_equal 32_766, sqlite.bind_limit
    end
  end

  describe ".unlimited" do
    it "is LIMIT -1, which SQLite needs before an OFFSET" do
      assert_equal [[3]], sqlite.connect(":memory:").execute("SELECT 3 #{sqlite.unlimited} OFFSET 0")
    end
  end

  describe ".sql_type" do
    it "maps each column type to the type a migration writes" do
      types = %i[integer float string bool date time enum uuid int32 int16 json].to_h do |type|
        [type, sqlite.sql_type(type)]
      end

      assert_equal(
        { integer: "INTEGER", float: "REAL", string: "TEXT", bool: "INTEGER", date: "TEXT", time: "TEXT",
          enum: "TEXT", uuid: "TEXT", int32: "INTEGER", int16: "INTEGER", json: "TEXT" },
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

  describe ".alters_in_place?" do
    it "is false, since SQLite can't change a column or a constraint, so a migration rebuilds the table" do
      refute_predicate sqlite, :alters_in_place?
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
        [:date, "text"],
        [:bool, "BOOLEAN"],
        [:date, "DATE"],
        [:time, "DATETIME"],
        [:time, "DATETIME(6)"],
        [:uuid, "varchar(36)"],
        [:int32, "int"],
        [:int16, "smallint"],
        [:json, "varchar"]
      ]

      assert(declared.all? { |type, sql_type| sqlite.compatible?(type, sql_type) })
    end

    it "refuses a declared type with another affinity" do
      declared = [[:integer, "TEXT"], [:string, "BLOB"], [:string, ""], [:time, "BLOB"], [:float, "NUMERIC"],
                  [:uuid, "BLOB"], [:int32, "TEXT"], [:int16, "REAL"], [:json, "JSON"]]

      assert(declared.none? { |type, sql_type| sqlite.compatible?(type, sql_type) })
    end
  end

  describe ".compatible? with NUMERIC affinity" do
    it "refuses every type but bool, date and time" do
      numeric = %w[NUMERIC DECIMAL(10,2) BOOLEAN DATETIME]
      refused = %i[integer float string enum].product(numeric)

      assert(refused.none? { |type, sql_type| sqlite.compatible?(type, sql_type) })
    end

    it "reads back == what was written to BOOLEAN, DATE and DATETIME(6) columns" do
      connection.execute_batch("CREATE TABLE events (done BOOLEAN, on_date DATE, at DATETIME(6))")
      written = [true, Date.new(2026, 11, 11), Time.utc(2026, 11, 11, 9, 30, 0, 123_456)]
      connection.execute("INSERT INTO events VALUES (?, ?, ?)", written.map { |value| sqlite.encode(value) })
      row = connection.execute("SELECT done, on_date, at FROM events").fetch(0)

      assert_equal(written, %i[bool date time].zip(row).map { |type, value| sqlite.decode(type, value) })
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

    it "reads JSON into a Hash, frozen at every level" do
      read = sqlite.decode(:json, +'{"list":[{"deep":"ü"}]}')

      assert_equal [{ "list" => [{ "deep" => "ü" }] }, true],
                   [read, [read, read["list"], read["list"][0], read["list"][0]["deep"]].all?(&:frozen?)]
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

    it "reads back what was written to a uuid, an int32 and an int16 column, as a frozen String and Integers" do
      connection.execute(
        "CREATE TABLE refined (id #{sqlite.sql_type(:uuid)}, logins #{sqlite.sql_type(:int32)}, " \
        "rank #{sqlite.sql_type(:int16)})"
      )
      written = ["0b9d5f2e-7c4a-4e1b-9f3d-2a6c8e0b1d4f", 2_147_483_647, -32_768]
      connection.execute("INSERT INTO refined VALUES (?, ?, ?)", written.map { |value| sqlite.encode(value) })
      read = connection.execute("SELECT * FROM refined").fetch(0).zip(%i[uuid int32 int16]).map do |value, type|
        sqlite.decode(type, value)
      end

      assert_equal [written, true], [read, read.fetch(0).frozen?]
    end
  end

  describe ".tables" do
    def table(name) = tables.find { |table| table.name == name }

    it "reads each column's declared type, nullability and default, with a primary key never null" do
      expected = [
        catalog::Column.new(name: :id, type: "INTEGER", nullable: false, default: nil, generated: nil),
        catalog::Column.new(name: :list_id, type: "INTEGER", nullable: false, default: nil, generated: nil),
        catalog::Column.new(name: :title, type: "varchar(200)", nullable: false, default: nil, generated: nil),
        catalog::Column.new(name: :done, type: "INTEGER", nullable: false, default: "0", generated: nil),
        catalog::Column.new(name: :code, type: "TEXT", nullable: true, default: nil, generated: nil)
      ]

      assert_equal expected, table(:todos).columns
    end

    it "reads a generated column, stored or virtual, with its expression and no default" do
      connection.execute(<<~SQL)
        CREATE TABLE searches (
          title TEXT NOT NULL,
          search TEXT NOT NULL GENERATED ALWAYS AS (lower(title)) STORED,
          length INTEGER AS (length(title)) VIRTUAL
        )
      SQL
      expected = [
        catalog::Column.new(name: :search, type: "TEXT", nullable: false, default: nil, generated: "lower(title)"),
        catalog::Column.new(name: :length, type: "INTEGER", nullable: true, default: nil, generated: "length(title)")
      ]

      assert_equal expected, table(:searches).columns.drop(1)
    end

    it "leaves out a virtual table's hidden columns" do
      connection.execute("CREATE VIRTUAL TABLE notes USING fts5(body)")

      assert_equal [:body], table(:notes).columns.map(&:name)
    end

    it "reads a default as a migration writes it, with an expression back in its parentheses" do
      connection = sqlite.connect(":memory:")
      connection.execute(<<~SQL)
        CREATE TABLE defaults (
          a TEXT DEFAULT 'it''s', b INTEGER DEFAULT -1, c REAL DEFAULT 1.5e3, d BLOB DEFAULT x'00',
          e TEXT DEFAULT NULL, f INTEGER DEFAULT true, g TEXT DEFAULT CURRENT_TIMESTAMP,
          h TEXT DEFAULT (lower('A')), i INTEGER DEFAULT 0x1F
        )
      SQL
      defaults = sqlite.tables(connection).fetch(0).columns.map(&:default)

      assert_equal ["'it''s'", "-1", "1.5e3", "x'00'", "NULL", "true", "(CURRENT_TIMESTAMP)", "(lower('A'))", "0x1F"],
                   defaults
    end

    it "reads each index, with its statement, but not those its constraints make" do
      expected = [
        catalog::Index.new(
          name: "todos_code_index",
          columns: [:code],
          unique: true,
          definition: "CREATE UNIQUE INDEX todos_code_index ON todos (code)"
        ),
        catalog::Index.new(
          name: "todos_list_id_done_index",
          columns: %i[list_id done],
          unique: false,
          definition: "CREATE INDEX todos_list_id_done_index ON todos (list_id, done)"
        )
      ]

      assert_equal expected, table(:todos).indexes
    end

    it "reads an index on an expression as having no columns" do
      expected = catalog::Index.new(
        name: "lists_slug_index",
        columns: [],
        unique: true,
        definition: "CREATE UNIQUE INDEX lists_slug_index ON lists (lower(slug))"
      )

      assert_equal [expected], table(:lists).indexes
    end

    it "reads each constraint from the CREATE TABLE" do
      expected = [
        catalog::Constraint.new(
          name: nil,
          kind: :primary_key,
          columns: [:id],
          references: nil,
          definition: "PRIMARY KEY (id)"
        ),
        catalog::Constraint.new(
          name: "todos_list_id_fkey",
          kind: :foreign_key,
          columns: [:list_id],
          references: :lists,
          definition: "FOREIGN KEY (list_id) REFERENCES lists ON DELETE RESTRICT"
        ),
        catalog::Constraint.new(
          name: "todos_title_check",
          kind: :check,
          columns: [:title],
          references: nil,
          definition: "CHECK (length(title) > 0)"
        ),
        catalog::Constraint.new(
          name: nil,
          kind: :check,
          columns: [:done],
          references: nil,
          definition: "CHECK (done IN (0, 1))"
        )
      ]

      assert_equal expected, table(:todos).constraints
    end

    it "leaves out SQLite's own tables, and reads a table with no indexes" do
      connection = sqlite.connect(":memory:")
      connection.execute("CREATE TABLE counters (id INTEGER PRIMARY KEY AUTOINCREMENT)")

      assert_equal([[:counters, []]], sqlite.tables(connection).map { |table| [table.name, table.indexes] })
    end
  end

  describe ".begin_migration" do
    it "turns foreign keys off, then takes SQLite's write lock as the transaction begins" do
      assert_equal "PRAGMA foreign_keys = OFF; BEGIN IMMEDIATE", sqlite.begin_migration
    end

    it "keeps the rows that refer to a table rebuilt in its transaction, which would cascade with foreign keys on" do
      cascading = sqlite.connect(":memory:")
      cascading.execute_batch(<<~SQL)
        CREATE TABLE lists (id INTEGER PRIMARY KEY);
        CREATE TABLE todos (id INTEGER PRIMARY KEY, list_id INTEGER NOT NULL REFERENCES lists ON DELETE CASCADE);
        INSERT INTO lists (id) VALUES (1);
        INSERT INTO todos (list_id) VALUES (1);
      SQL
      cascading.execute_batch(sqlite.begin_migration)
      cascading.execute_batch(<<~SQL)
        CREATE TABLE new_lists (id INTEGER PRIMARY KEY, name TEXT);
        INSERT INTO new_lists (id) SELECT id FROM lists;
        DROP TABLE lists;
        ALTER TABLE new_lists RENAME TO lists;
        COMMIT;
      SQL

      assert_equal [[1, 1]], cascading.execute("SELECT id, list_id FROM todos")
    end
  end

  describe ".foreign_key_violations" do
    it "describes each row that refers to a missing one" do
      connection.execute("PRAGMA foreign_keys = OFF")
      connection.execute("INSERT INTO todos (list_id, title) VALUES (9, 'Eggs')")

      assert_equal ["todos row 2 refers to a missing lists row (foreign key 0)"],
                   sqlite.foreign_key_violations(connection)
    end

    it "has none when every reference is there" do
      assert_empty sqlite.foreign_key_violations(connection)
    end
  end

  describe ".end_migration" do
    it "turns foreign keys back on" do
      assert_equal "PRAGMA foreign_keys = ON", sqlite.end_migration
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

    it "reads a check's columns from any table when it isn't told which was written" do
      assert_equal violation_of(:check, "todos_title_check", [:title], "CHECK constraint failed: todos_title_check"),
                   violation("INSERT INTO todos (list_id, title) VALUES (1, '')", nil)
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

    it "reads the one foreign key any table has when it isn't told which was written" do
      assert_equal violation_of(:foreign_key, "todos_list_id_fkey", [:list_id], "FOREIGN KEY constraint failed"),
                   violation("INSERT INTO todos (list_id, title) VALUES (9, 'Eggs')", nil)
    end

    it "can't say which foreign key failed when it isn't told which table was written and the tables have more" do
      connection.execute("CREATE TABLE shares (list_id INTEGER REFERENCES lists)")

      assert_equal violation_of(:foreign_key, nil, [], "FOREIGN KEY constraint failed"),
                   violation("INSERT INTO todos (list_id, title) VALUES (9, 'Eggs')", nil)
    end

    it "is nil for a constraint it doesn't report, such as a trigger's" do
      connection.execute("CREATE TRIGGER no_lists BEFORE INSERT ON lists BEGIN SELECT RAISE(ABORT, 'no'); END")

      assert_nil violation("INSERT INTO lists (name) VALUES ('Work')", :lists)
    end
  end
end
