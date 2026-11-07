# frozen_string_literal: true

require "test_helper"
require "release"

describe Release do
  let(:source) { %(module Skyward\n  VERSION = "0.1.0" #: String\nend\n) }

  describe ".version" do
    it "reads the version from a version.rb" do
      assert_equal "0.1.0", Release.version(source)
    end

    it "returns nil for a file with no version" do
      assert_nil Release.version("module Skyward\nend\n")
    end
  end

  describe ".shared" do
    it "returns the version every source agrees on" do
      assert_equal "0.1.0", Release.shared([source, source])
    end

    it "returns nil when the sources disagree" do
      assert_nil Release.shared([source, source.sub("0.1.0", "0.2.0")])
    end
  end
end
