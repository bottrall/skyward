# frozen_string_literal: true

require "test_helper"

describe HealthAPI do
  describe "#show" do
    it "says the app is up" do
      assert_equal({ status: "ok" }, HealthAPI.new.show)
    end
  end
end
