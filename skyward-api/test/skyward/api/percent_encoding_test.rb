# frozen_string_literal: true

require "test_helper"

describe Skyward::API::PercentEncoding do
  describe ".decode" do
    it "decodes each escape, %2F included" do
      assert_equal "a/b c", Skyward::API::PercentEncoding.decode("a%2Fb%20c")
    end

    it "decodes as UTF-8" do
      assert_equal "café", Skyward::API::PercentEncoding.decode("caf%C3%A9")
    end

    it "leaves a malformed escape as it is" do
      assert_equal "100%zz", Skyward::API::PercentEncoding.decode("100%zz")
    end
  end
end
