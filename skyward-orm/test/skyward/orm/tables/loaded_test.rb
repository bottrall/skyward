# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Tables::Loaded do
  describe ".table_classes" do
    it "finds a subclass with a table at any depth, under subclasses without one" do
      base = Class.new(Skyward::ORM::Record)
      shared = Class.new(base)
      projects = Class.new(shared) do
        table :projects
        attr_reader :id
      end
      archived = Class.new(projects) do
        table :archived
        attr_reader :id
      end

      assert_equal [archived, projects].sort_by(&:to_s), Skyward::ORM::Tables::Loaded.table_classes(base)
    end

    it "lists them by name" do
      named = [TablesFixtures::List, TablesFixtures::Todo]

      assert_equal named, Skyward::ORM::Tables::Loaded.table_classes(Skyward::ORM::Record) & named
    end
  end
end
