# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../fixtures/tables/tables_fixtures"

describe Skyward::ORM do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "registers its signatures, which an app's table classes subclass" do
    builder = Skyward::Core::Signatures.load(File.expand_path("missing", __dir__))

    assert builder.env.class_decl?(RBS::TypeName.parse("::Skyward::ORM::Record"))
  end
end

describe Skyward do
  fixtures = File.expand_path("../fixtures/tables", __dir__)

  describe ".connect" do
    todo = TablesFixtures::Todo
    values = [1, 1, "Buy milk", "normal", nil, 0, "2026-10-18 09:30:00.000000"]

    it "keeps the database it connects to, for every query" do
      database = Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))

      assert_same database, Skyward::ORM::Connection::SESSION.database
    end

    it "reads column types from the signatures given" do
      database = Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))

      assert_equal :normal, database.decoder(todo, todo).call(values).priority
    end

    it "reads them from sig/ in the current directory by default" do
      database = Dir.chdir(fixtures) { Skyward.connect("sqlite://:memory:") }

      assert_equal :normal, database.decoder(todo, todo).call(values).priority
    end

    it "opens up to pool: connections" do
      Dir.mktmpdir do |dir|
        database = Skyward.connect(
          "sqlite://#{File.join(dir, "todos.db")}",
          signatures: File.join(fixtures, "sig"),
          pool: 2
        )
        outer, inner = database.connection { |first| database.connection { |second| [first, second] } }

        refute_same outer, inner
      end
    end
  end

  describe ".transaction" do
    it "runs the block in a transaction on the connected database" do
      Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))

      assert(Skyward.transaction { Skyward.transaction? })
    end
  end

  describe ".transaction?" do
    it "is false outside a transaction on the connected database" do
      Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))

      refute_predicate Skyward, :transaction?
    end
  end

  describe ".query" do
    before do
      Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))
      Skyward.query("CREATE TABLE todos (title TEXT NOT NULL, due_on TEXT, done INTEGER NOT NULL)")
      Skyward.query("INSERT INTO todos VALUES (?, ?, ?)", "Milk", Date.new(2026, 10, 1), false)
      Skyward.query("INSERT INTO todos VALUES (?, ?, ?)", "Eggs", Date.today + 1, false)
    end

    it "returns symbol-keyed hashes when the SQL comes first" do
      assert_equal [{ title: "Milk" }], Skyward.query("SELECT title FROM todos WHERE due_on < ?", Date.today)
    end

    it "returns the README's Overdue rows, with days_late an Integer" do
      rows = Skyward.query(TablesFixtures::Overdue, <<~SQL, Date.today)
        SELECT title, current_date - due_on AS days_late
        FROM todos
        WHERE due_on < ? AND NOT done
        ORDER BY days_late DESC
      SQL

      assert_equal(
        [[TablesFixtures::Overdue, "Milk", Integer]],
        rows.map { |row| [row.class, row.title, row.days_late.class] }
      )
    end

    it "refuses anything else first" do
      error = assert_raises(ArgumentError) { Skyward.query(:todos, "SELECT 1") }

      assert_equal "Skyward.query takes a row class or the SQL as its first argument", error.message
    end
  end

  describe ".sql" do
    it "wraps an SQL expression" do
      assert_equal Skyward::ORM::Tables::SQL.new(expression: "now()"), Skyward.sql("now()")
    end

    it "keeps a frozen copy" do
      assert_predicate Skyward.sql(+"now()").expression, :frozen?
    end

    it "refuses anything but a String" do
      error = assert_raises(ArgumentError) { Skyward.sql(:now) }

      assert_equal "Skyward.sql takes the SQL as a String, not :now", error.message
    end
  end
end
