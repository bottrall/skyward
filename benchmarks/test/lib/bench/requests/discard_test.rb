# frozen_string_literal: true

require "test_helper"

describe Bench::Requests::Discard do
  describe ".info" do
    it "drops the line" do
      assert_silent { Bench::Requests::Discard.info("{}") }
    end
  end
end
