# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Connection::Database do
  sqlite = Skyward::ORM::Adapters::SQLite
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))

  let(:connection) do
    sqlite.connect(":memory:").tap do |connection|
      connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT CONSTRAINT lists_name_key UNIQUE)")
      connection.execute("INSERT INTO lists (name) VALUES ('Home')")
    end
  end
  let(:database) do
    Skyward::ORM::Connection::Database.new(
      sqlite,
      connection,
      Skyward::ORM::Tables::ColumnTypes.new(reader),
      sqlite.tables(connection)
    )
  end
  let(:todo) { TablesFixtures::Todo }

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
