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
