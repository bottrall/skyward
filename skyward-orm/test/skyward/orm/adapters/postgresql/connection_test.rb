# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Adapters::PostgreSQL::Connection do
  let(:connection) { TestDatabase.empty("postgresql").connect }

  describe "#execute" do
    it "returns each row's values, bound to numbered placeholders" do
      assert_equal [%w[Milk 2]], connection.execute("SELECT $1::text, $2::bigint", ["Milk", 2])
    end

    it "runs SQL with nothing to bind" do
      assert_equal [["1"]], connection.execute("SELECT 1")
    end
  end

  describe "#execute2" do
    it "returns the column names, then each row's values" do
      assert_equal [%w[title done], %w[Milk t]],
                   connection.execute2("SELECT $1::text AS title, $2::boolean AS done", "Milk", true)
    end

    it "names the columns when there are no rows" do
      assert_equal [["title"]], connection.execute2("SELECT 'Milk' AS title WHERE false")
    end
  end

  describe "#execute_batch" do
    it "runs every statement in the SQL" do
      connection.execute_batch("CREATE TABLE lists (name text); INSERT INTO lists VALUES ('Home');")

      assert_equal [["Home"]], connection.execute("SELECT name FROM lists")
    end
  end
end
