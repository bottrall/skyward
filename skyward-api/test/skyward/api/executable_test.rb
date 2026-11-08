# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Executable do
  describe ".find" do
    it "finds the executable of a gem in the bundle" do
      assert_equal Gem.bin_path("rake", "rake"), Skyward::API::Executable.find("rake")
    end

    it "finds a gem in the bundle by the file it's required by" do
      assert_equal Gem.bin_path("rbs-inline", "rbs-inline"),
                   Skyward::API::Executable.find("rbs-inline", feature: "rbs/inline")
    end

    it "returns nil for a gem the bundle doesn't have" do
      assert_nil Skyward::API::Executable.find("falcon")
    end
  end
end
