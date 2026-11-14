# frozen_string_literal: true

require "test_helper"

describe Bench::RoutesAPI do
  let(:api) { Bench::RoutesAPI.new }

  it "declares twenty routes" do
    assert_equal 20, Bench::RoutesAPI.routes.size
  end

  describe "#list" do
    it "answers no rows" do
      assert_empty api.list
    end
  end

  describe "#show" do
    it "answers the id" do
      assert_equal({ id: 42 }, api.show(id: 42))
    end
  end

  describe "#part" do
    it "answers both ids" do
      assert_equal({ id: 42, part_id: 7 }, api.part(id: 42, part_id: 7))
    end
  end

  describe "#line" do
    it "answers both ids" do
      assert_equal({ id: 42, line_id: 7 }, api.line(id: 42, line_id: 7))
    end
  end
end
