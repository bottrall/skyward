# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "tmpdir"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Connection::Database do
  sqlite = Skyward::ORM::Adapters::SQLite
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))
  refused = Skyward::ORM::Violation.new(kind: :check, constraint: nil, columns: [], message: "refused")
  foreign = "this transaction belongs to another fiber; start your own, or return the result to the block"

  counting_adapter = Class.new do
    attr_reader :comparisons

    def initialize(adapter)
      @adapter = adapter
    end

    def compatible?(type, sql_type)
      @comparisons = comparisons.to_i + 1
      @adapter.compatible?(type, sql_type)
    end

    def sql_type(type) = @adapter.sql_type(type)
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
    Skyward::ORM::Connection::Database.new(
      adapter,
      Skyward::ORM::Connection::Pool.new(1, -> { connection }),
      column_types,
      sqlite.tables(connection),
      check:
    )
  end
  # Each connection to :memory: is a database of its own, so these are told
  # apart only by identity.
  let(:two_connections) { pooled(-> { sqlite.connect(":memory:") }) }
  let(:todo) { TablesFixtures::Todo }
  let(:list) { TablesFixtures::List }

  def mismatch(table)
    Skyward::ORM::Connection::Database::SchemaCheck.mismatch(
      table, column_types.columns(table), adapter.tables(connection), adapter
    )
  end

  def pooled(opener)
    Skyward::ORM::Connection::Database.new(
      Skyward::ORM::Adapters::SQLite,
      Skyward::ORM::Connection::Pool.new(2, opener),
      column_types,
      [],
      check: false
    )
  end

  def insert(database, name)
    database.connection { |connection| connection.execute("INSERT INTO lists (name) VALUES (?)", [name]) }
  end

  def names(database = self.database)
    database.connection { |connection| connection.execute("SELECT name FROM lists ORDER BY id") }
  end

  # A file, so every connection in the pool opens the same database.
  def in_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "todos.db")
      database = pooled(-> { Skyward::ORM::Adapters::SQLite.connect(path) })
      database.connection { |connection| connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT)") }
      yield database
    end
  end

  describe "#connection" do
    it "checks one out for the query alone outside a transaction" do
      assert_same(connection, database.connection { |checked_out| checked_out })
    end

    it "refuses a child fiber the transaction it inherited" do
      error = assert_raises(FiberError) do
        database.transaction { Fiber.new { database.connection { nil } }.resume }
      end

      assert_equal foreign, error.message
    end

    it "refuses a thread the transaction it inherited" do
      error = database.transaction do
        Thread.new do
          database.connection { nil }
        rescue FiberError => e
          e
        end.value
      end

      assert_equal foreign, error.message
    end

    it "yields the transaction's inside one, on the fiber that opened it" do
      database = two_connections
      outer, inner = database.transaction do
        database.connection { |first| database.connection { |second| [first, second] } }
      end

      assert_same outer, inner
    end
  end

  describe "#transaction" do
    it "nests as a savepoint, which rolls back only its own writes" do
      database.transaction do
        insert(database, "Work")
        database.transaction do
          insert(database, "Garden")
          refused
        end
        :done
      end

      assert_equal [["Home"], ["Work"]], names
    end

    it "rolls a nested one back when its block raises, keeping the outer one's writes" do
      database.transaction do
        insert(database, "Work")
        begin
          database.transaction do
            insert(database, "Garden")
            raise "failed"
          end
        rescue RuntimeError
          nil
        end
        insert(database, "Shed")
      end

      assert_equal [["Home"], ["Work"], ["Shed"]], names
    end

    it "commits a nested one with the outer one" do
      database.transaction do
        database.transaction { insert(database, "Work") }
      end

      assert_equal [["Home"], ["Work"]], names
    end

    it "commits, and returns the block's value" do
      value = database.transaction do
        insert(database, "Work")
        :done
      end

      assert_equal [:done, [["Home"], ["Work"]]], [value, names]
    end

    it "rolls back and raises again when the block raises" do
      assert_raises(RuntimeError) do
        database.transaction do
          insert(database, "Work")
          raise "failed"
        end
      end

      assert_equal [["Home"]], names
    end

    it "rolls back and returns a violation the block returns" do
      value = database.transaction do
        insert(database, "Work")
        refused
      end

      assert_equal [refused, [["Home"]]], [value, names]
    end

    it "rolls back when the commit fails, so its connection goes back with no transaction open" do
      database.connection do |connection|
        connection.execute("CREATE TABLE shares (list_id INTEGER REFERENCES lists DEFERRABLE INITIALLY DEFERRED)")
      end
      assert_raises(SQLite3::ConstraintException) do
        database.transaction do
          database.connection do |connection|
            connection.execute("INSERT INTO shares VALUES (9)")
          end
        end
      end

      assert_equal(:begun, database.transaction { :begun })
    end

    it "leaves the fiber outside a transaction afterwards, even when the block raises" do
      assert_raises(RuntimeError) { database.transaction { raise "failed" } }

      refute_predicate database, :transaction?
    end

    it "starts its own in a child fiber that inherited another's" do
      database = two_connections

      assert(database.transaction { Fiber.new { database.transaction { database.transaction? } }.resume })
    end

    it "leaves another thread's write in place when it rolls back" do
      in_file do |database|
        begun = Thread::Queue.new
        written = Thread::Queue.new
        rolled_back = Thread.new do
          database.transaction do
            begun << true
            written.pop
            insert(database, "Work")
            refused
          end
        end
        begun.pop
        insert(database, "Home")
        written << true
        rolled_back.join

        assert_equal [["Home"]], names(database)
      end
    end

    it "leaves another fiber's write in place when it rolls back, after being suspended mid-block" do
      in_file do |database|
        rolled_back = Fiber.new do
          database.transaction do
            Fiber.yield
            insert(database, "Work")
            refused
          end
        end
        rolled_back.resume
        Fiber.new { insert(database, "Home") }.resume
        rolled_back.resume

        assert_equal [["Home"]], names(database)
      end
    end
  end

  describe "#transaction?" do
    it "is false outside a transaction" do
      refute_predicate database, :transaction?
    end

    it "is true inside one, on the fiber that opened it" do
      assert(database.transaction { database.transaction? })
    end

    it "is false in a held transaction" do
      database.hold

      refute_predicate database, :transaction?
    ensure
      database.release
    end

    it "is true inside a transaction in a held one, and false again after it" do
      database.hold

      assert_equal [true, false], [database.transaction { database.transaction? }, database.transaction?]
    ensure
      database.release
    end

    it "is false in a child fiber that inherited it" do
      refute(database.transaction { Fiber.new { database.transaction? }.resume })
    end

    it "is false in a thread that inherited it" do
      refute(database.transaction { Thread.new { database.transaction? }.value })
    end
  end

  describe "#hold" do
    it "runs its fiber's queries on the connection it holds" do
      database = two_connections
      database.hold
      outer, inner = database.connection { |first| database.connection { |second| [first, second] } }

      assert_same outer, inner
    ensure
      database.release
    end

    it "refuses a child fiber the connection it holds" do
      database.hold
      error = assert_raises(FiberError) { Fiber.new { database.connection { nil } }.resume }

      assert_equal foreign, error.message
    ensure
      database.release
    end

    it "refuses a thread the connection it holds" do
      database.hold
      error = Thread.new do
        database.connection { nil }
      rescue FiberError => e
        e
      end.value

      assert_equal foreign, error.message
    ensure
      database.release
    end

    it "nests a transaction as a savepoint, which rolls back only its own writes" do
      database.hold
      insert(database, "Work")
      database.transaction do
        insert(database, "Garden")
        refused
      end

      assert_equal [["Home"], ["Work"]], names
    ensure
      database.release
    end
  end

  describe "#release" do
    it "does nothing when nothing is held" do
      assert_nil database.release
    end

    it "rolls back what was written while held" do
      database.hold
      insert(database, "Work")
      database.release

      assert_equal [["Home"]], names
    end

    it "returns the connection to the pool, and leaves the fiber holding nothing" do
      database.hold
      database.release

      assert_same(connection, Fiber.new { database.connection { |checked_out| checked_out } }.resume)
    end

    it "returns the connection even when the rollback fails" do
      database.hold
      database.execute("COMMIT")
      assert_raises(SQLite3::SQLException) { database.release }

      assert_same(connection, Fiber.new { database.connection { |checked_out| checked_out } }.resume)
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
      assert_equal %i[lists todos], database.tables.map(&:name)
    end
  end

  describe "#execute" do
    it "runs SQL on its connection and returns the rows" do
      assert_equal [["Home"]], database.execute("SELECT name FROM lists")
    end

    it "binds its values to the SQL's placeholders" do
      assert_equal [["Home"]], database.execute("SELECT name FROM lists WHERE id = ?", [1])
    end
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

  describe "#decoder" do
    let(:values) { [1, 1, "Buy milk", "normal", nil, 0, "2026-10-18 09:30:00.000000"] }

    it "checks its table class first" do
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.decoder(list, list, []) }

      assert_equal mismatch(list), error.message
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

      assert_equal expected, database.decoder(todo, todo, []).call(values)
    end

    it "builds a table's decoder once" do
      assert_same database.decoder(todo, todo, []), database.decoder(todo, todo, [])
    end

    it "builds one for each row class" do
      summary = Class.new(Skyward::ORM::Record) { attr_reader :done }

      refute_same database.decoder(todo, todo, []), database.decoder(todo, summary, [])
    end

    it "builds one for each set of expressed members" do
      summary = Data.define(:done)

      refute_same database.decoder(todo, summary, []), database.decoder(todo, summary, [:done])
    end

    it "reads a member by the row class's own type before its table's column type" do
      assert_equal TablesFixtures::Labelled.new(priority: "high"),
                   database.decoder(todo, TablesFixtures::Labelled, []).call(["high"])
    end

    it "reads an expressed member by the row class's own type" do
      assert_equal TablesFixtures::Progress.new(list_id: 1, finished: true),
                   database.decoder(todo, TablesFixtures::Progress, [:finished]).call([1, 1])
    end

    it "reads a member the row class doesn't type by its table's column of that name" do
      summary = Data.define(:title, :done)

      assert_equal summary.new(title: "Buy milk", done: true), database.decoder(todo, summary, []).call(["Buy milk", 1])
    end

    it "passes through an expressed member the row class doesn't type, even one named like a column" do
      summary = Data.define(:done)

      assert_equal summary.new(done: 3), database.decoder(todo, summary, [:done]).call([3])
    end

    it "passes through a member its table has no column for" do
      late = Class.new(Skyward::ORM::Record) { attr_reader :days_late }

      assert_equal late.new(days_late: 3), database.decoder(todo, late, []).call([3])
    end
  end

  describe "#prepare" do
    it "checks the table class" do
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.prepare(list) }

      assert_equal mismatch(list), error.message
    end

    describe "with the check off" do
      let(:check) { false }

      it "doesn't check it" do
        assert_silent { database.prepare(list) }
      end
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

  describe "#hashes" do
    it "returns each row as its columns" do
      assert_equal [{ id: 1, name: "Home" }], database.hashes("SELECT id, name FROM lists", [])
    end

    it "binds each value as a parameter, as the adapter stores it, and returns values as the driver does" do
      assert_equal [{ done: 1, due_on: "2026-10-01" }],
                   database.hashes("SELECT ? AS done, ? AS due_on", [true, Date.new(2026, 10, 1)])
    end

    it "refuses an Array, which the driver would spread across several ?, naming its position" do
      error = assert_raises(ArgumentError) { database.hashes("SELECT ?", [[1, 2]]) }

      assert_equal "Skyward.query binds one value to each ?, but value 1 is an Array", error.message
    end

    it "refuses an empty Array, which the driver would bind to no ?" do
      assert_raises(ArgumentError) { database.hashes("SELECT ?", [[]]) }
    end

    it "refuses a Hash, naming its position" do
      error = assert_raises(ArgumentError) { database.hashes("SELECT ?, ?", [1, {}]) }

      assert_equal "Skyward.query binds one value to each ?, but value 2 is a Hash", error.message
    end

    it "refuses values that would move the ones after them to other ?" do
      assert_raises(ArgumentError) do
        database.hashes("SELECT name FROM lists WHERE name = ? AND id = ? LIMIT ?", [["Home", 1], 2, {}])
      end
    end

    it "runs in the fiber's transaction, seeing a write it hasn't committed" do
      in_file do |database|
        seen = database.transaction do
          insert(database, "Work")
          database.hashes("SELECT name FROM lists", [])
        end

        assert_equal [{ name: "Work" }], seen
      end
    end

    it "raises a violation the SQL causes" do
      error = assert_raises(Skyward::ORM::ViolationError) do
        database.hashes("INSERT INTO lists (name) VALUES (?)", ["Home"])
      end

      assert_equal [:unique, "lists_name_key"], [error.violation.kind, error.violation.constraint]
    end

    it "raises any other error as it is" do
      assert_raises(SQLite3::SQLException) { database.hashes("SELECT * FROM missing", []) }
    end
  end

  describe "#rows" do
    let(:overdue) { TablesFixtures::Overdue }
    let(:due) { TablesFixtures::Due }

    it "builds the row class from the SQL's columns, by name" do
      assert_equal [overdue.new(title: "Home", days_late: 3)],
                   database.rows(overdue, "SELECT ? AS days_late, name AS title FROM lists", [3])
    end

    it "reads each member by its type, and passes an untyped one through, frozen" do
      row = database.rows(due, "SELECT 'Milk' AS title, '2026-10-01' AS due_on, 'cold' AS note", []).fetch(0)

      assert_equal [due.new(title: "Milk", due_on: Date.new(2026, 10, 1), note: "cold"), true], [row, row.note.frozen?]
    end

    it "reads NULL as nil" do
      assert_equal [due.new(title: "Milk", due_on: nil, note: nil)],
                   database.rows(due, "SELECT 'Milk' AS title, NULL AS due_on, NULL AS note", [])
    end

    it "refuses a column the row class has no member for, naming it" do
      error = assert_raises(ArgumentError) do
        database.rows(overdue, "SELECT name AS title, 3 AS days_late, id, 1 AS done FROM lists", [])
      end

      assert_equal "TablesFixtures::Overdue has no member for id, done, which the SQL returns", error.message
    end

    it "refuses a member the SQL returns no column for, naming it, even with no rows" do
      error = assert_raises(ArgumentError) do
        database.rows(overdue, "SELECT name AS title FROM lists WHERE id = 0", [])
      end

      assert_equal "The SQL returns no days_late for TablesFixtures::Overdue", error.message
    end
  end

  describe "#migrate" do
    runner = Skyward::ORM::Migrations::Runner
    create_notes = runner.parse("20261001000000_create_notes.sql", "CREATE TABLE notes (id INTEGER);\n")
    note = Class.new(Skyward::ORM::Record) do
      table :notes
      attr_reader :id
    end

    it "runs the migrations on a connection it checks out, through its adapter" do
      ran = database.migrate([create_notes])

      assert_equal [["20261001000000"], [["notes"]]],
                   [ran, connection.execute("SELECT name FROM sqlite_schema WHERE name = 'notes'")]
    end

    it "reads the schema again, so a class is checked against the tables the migrations made" do
      database.migrate([create_notes])

      assert_silent { database.check([note]) }
    end

    it "checks a class again against the schema it migrated to, though it matched before" do
      database.check([todo])
      database.migrate([runner.parse("20261001000000_drop_title.sql", "ALTER TABLE todos DROP COLUMN title;\n")])
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.check([todo]) }

      assert_equal mismatch(todo), error.message
    end
  end

  describe "#write" do
    it "checks its table class before it writes" do
      assert_raises(Skyward::ORM::SchemaMismatch) do
        database.write(list, list, "DELETE FROM missing RETURNING id, name", [])
      end
    end

    describe "with the check off" do
      let(:check) { false }

      it "returns the rows the write returns, as the table's rows" do
        assert_equal [list.new(id: 2, name: "Work")],
                     database.write(list, list, "INSERT INTO lists (name) VALUES (?) RETURNING id, name", ["Work"])
      end

      it "returns a violation the write causes, filled in for the table written" do
        expected = Skyward::ORM::Violation.new(
          kind: :unique,
          constraint: "lists_name_key",
          columns: [:name],
          message: "UNIQUE constraint failed: lists.name"
        )

        assert_equal expected,
                     database.write(list, list, "INSERT INTO lists (name) VALUES (?) RETURNING id, name", ["Home"])
      end

      it "raises any other error as it is" do
        assert_raises(SQLite3::SQLException) { database.write(list, list, "DELETE FROM missing RETURNING id, name", []) }
      end
    end
  end
end
