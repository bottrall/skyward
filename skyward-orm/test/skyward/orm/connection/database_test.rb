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

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }
  let(:connection) do
    sqlite.connect(":memory:").tap do |connection|
      connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT CONSTRAINT lists_name_key UNIQUE)")
      connection.execute("INSERT INTO lists (name) VALUES ('Home')")
    end
  end
  let(:database) do
    Skyward::ORM::Connection::Database.new(
      sqlite,
      Skyward::ORM::Connection::Pool.new(1, -> { connection }),
      column_types,
      sqlite.tables(connection)
    )
  end
  # Each connection to :memory: is a database of its own, so these are told
  # apart only by identity.
  let(:two_connections) { pooled(-> { sqlite.connect(":memory:") }) }
  let(:todo) { TablesFixtures::Todo }

  def pooled(opener)
    Skyward::ORM::Connection::Database.new(
      Skyward::ORM::Adapters::SQLite,
      Skyward::ORM::Connection::Pool.new(2, opener),
      column_types,
      []
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
