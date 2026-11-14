# frozen_string_literal: true

require "test_helper"

describe Bench::Environment do
  describe ".describe" do
    def describe_with(ruby: "ruby 3.4.7 +PRISM [x86_64-linux]", cpuinfo: nil)
      Bench::Environment.describe(commit: "abc123", ruby:, cpuinfo:)
    end

    it "records the Skyward version, the commit and the Ruby" do
      assert_equal [Skyward::Core::VERSION, "abc123", "ruby 3.4.7 +PRISM [x86_64-linux]"],
                   describe_with.values_at(:skyward, :commit, :ruby)
    end

    it "records YJIT as on when Ruby's description says so" do
      assert describe_with(ruby: "ruby 3.4.7 +YJIT +PRISM [x86_64-linux]").fetch(:yjit)
    end

    it "records YJIT as off otherwise" do
      refute describe_with.fetch(:yjit)
    end

    it "records the CPU's model from /proc/cpuinfo" do
      cpuinfo = "processor\t: 0\nmodel name\t: AMD EPYC 7763 64-Core Processor\nmodel name\t: AMD EPYC 7763\n"

      assert_equal "AMD EPYC 7763 64-Core Processor", describe_with(cpuinfo:).fetch(:cpu)
    end

    it "records no CPU without /proc/cpuinfo" do
      assert_nil describe_with.fetch(:cpu)
    end

    it "leaves each database's version to the group that connects to it" do
      assert_equal [nil, nil], describe_with.values_at(:sqlite, :postgresql)
    end
  end
end
