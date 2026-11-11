# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Tables::Members do
  members = Skyward::ORM::Tables::Members

  describe ".of" do
    it "is a Data class's members" do
      assert_equal %i[title days_late], members.of(TablesFixtures::Overdue)
    end

    it "is any other class's keyword parameters, required or not" do
      late = Class.new do
        def initialize(title, *rest, days_late:, note: nil, **options); end
      end

      assert_equal %i[days_late note], members.of(late)
    end
  end
end
