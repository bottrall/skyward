# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Record do
  let(:list) { TablesFixtures::List.new(id: 1, name: "Home") }

  it "gives every table class the declarations" do
    assert_kind_of Skyward::ORM::Tables::Declarations, Skyward::ORM::Record
  end

  it "builds rows of no columns until a table class declares some" do
    assert_empty Skyward::ORM::Record.new.to_h
  end

  describe "querying the connected database" do
    let(:session) { Skyward::ORM::Connection::SESSION }
    let(:all) { Skyward::ORM::Query.new(TablesFixtures::List, session) }

    let(:connection) do
      Skyward::ORM::Adapters::SQLite.connect(":memory:").tap do |connection|
        connection.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT)")
      end
    end

    before do
      session.connect(
        Skyward::ORM::Connection::Database.new(
          Skyward::ORM::Adapters::SQLite,
          Skyward::ORM::Connection::Pool.new(1, -> { connection }),
          Skyward::ORM::Tables::ColumnTypes.new(
            Skyward::Core::Types::Reader.new(
              Skyward::Core::Signatures.load(File.expand_path("../../fixtures/tables/sig", __dir__))
            )
          ),
          Skyward::ORM::Adapters::SQLite.tables(connection),
          check: false
        )
      )
    end

    describe ".all" do
      it "is a query of every row" do
        assert_equal all.to_sql, TablesFixtures::List.all.to_sql
      end
    end

    describe ".where" do
      it "starts from every row" do
        assert_equal all.where(name: "Work").to_sql, TablesFixtures::List.where(name: "Work").to_sql
      end
    end

    describe ".order" do
      it "starts from every row" do
        assert_equal all.order(name: :desc).to_sql, TablesFixtures::List.order(name: :desc).to_sql
      end
    end

    describe ".find_by" do
      it "starts from every row" do
        connection.execute("INSERT INTO lists VALUES (2, 'Work')")

        assert_equal all.where(name: "Work").first, TablesFixtures::List.find_by(name: "Work")
      end
    end
  end

  describe "#initialize" do
    it "sets the columns" do
      assert_equal({ id: 1, name: "Home" }, list.to_h)
    end

    it "freezes the row" do
      assert_predicate list, :frozen?
    end
  end

  describe "#with" do
    it "returns a copy with the changes" do
      assert_equal TablesFixtures::List.new(id: 1, name: "Work"), list.with(name: "Work")
    end

    it "leaves the row as it was" do
      list.with(name: "Work")

      assert_equal "Home", list.name
    end
  end

  describe "#deconstruct_keys" do
    it "matches a pattern" do
      matched =
        case list
        in { name: "Home" } then true
        else false
        end

      assert matched
    end

    it "is every column when every key is asked for" do
      assert_equal({ id: 1, name: "Home" }, list.deconstruct_keys(nil))
    end
  end

  describe "#inspect" do
    it "shows the class and each column" do
      todo = TablesFixtures::Todo.new(
        id: 1,
        list_id: 1,
        title: "Buy milk",
        priority: :normal,
        due_on: nil,
        done: false,
        created_at: Time.at(0, in: "UTC")
      )

      assert_equal "#<TablesFixtures::Todo id=1, list_id=1, title=\"Buy milk\", priority=:normal, due_on=nil, " \
                   "done=false, created_at=1970-01-01 00:00:00 UTC>",
                   todo.inspect
    end
  end
end
