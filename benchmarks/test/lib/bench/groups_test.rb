# frozen_string_literal: true

require "test_helper"

describe Bench::Groups do
  groups = Bench::Groups

  def scenario(name)
    Bench::Scenario.new(name:, run: -> {}, answer: ->(_) { {} }, expected: {}, unit: nil, per_iteration: 1)
  end

  describe ".scenarios" do
    it "builds each group's scenarios, whose names start with the group's" do
      Bench::Groups::ALL.each do |group|
        names = groups.scenarios(group).map(&:name)

        refute_empty names
        assert(names.all? { |name| name.start_with?("#{group}.") }, "#{group}: #{names}")
      end
    end
  end

  describe ".unmatched" do
    let(:names) { %w[api.get api.routes.first] }

    it "finds none when a scenario's name starts with each name" do
      assert_empty groups.unmatched(%w[api api.routes], names)
    end

    it "finds each name no scenario's starts with" do
      assert_equal %w[api.foo nope], groups.unmatched(%w[api api.foo nope], names)
    end
  end

  describe ".selected" do
    it "selects every group without names" do
      assert_equal %w[api orm.sqlite orm.postgresql], groups.selected([])
    end

    it "selects each group whose name starts with a name" do
      assert_equal %w[orm.sqlite orm.postgresql], groups.selected(%w[orm])
    end

    it "selects the group of a scenario's name" do
      assert_equal %w[api orm.sqlite], groups.selected(%w[api.routes orm.sqlite.rows.1])
    end

    it "selects no group for a name nothing starts with" do
      assert_empty groups.selected(%w[nope])
    end
  end

  describe ".skipped" do
    it "skips PostgreSQL's group without TEST_POSTGRES_URL" do
      assert_equal({ "orm.postgresql" => "TEST_POSTGRES_URL isn't set" }, groups.skipped(%w[orm.postgresql], nil))
    end

    it "skips nothing with TEST_POSTGRES_URL" do
      assert_empty groups.skipped(%w[orm.postgresql], "postgres://localhost/bench")
    end

    it "skips nothing when PostgreSQL's group isn't selected" do
      assert_empty groups.skipped(%w[api], nil)
    end
  end

  describe ".matching" do
    let(:scenarios) { %w[api.get api.routes.first api.routes.last].map { |name| scenario(name) } }

    it "keeps every scenario without names" do
      assert_equal scenarios, groups.matching(scenarios, [])
    end

    it "keeps each scenario whose name starts with a name" do
      assert_equal %w[api.routes.first api.routes.last], groups.matching(scenarios, %w[api.routes]).map(&:name)
    end
  end
end
