# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/boot/boot_fixtures"

describe Skyward::Test do
  describe ".client" do
    it "drives a Skyward app" do
      signatures = File.expand_path("../fixtures/boot/sig", __dir__)
      app = Skyward.app(signatures:, logger: nil) { |builder| builder.mount BootFixtures::Hello.new, at: "/hello" }
      client = Skyward::Test.client(app)

      assert_equal({ message: "Hello, ruby" }, client.get("/hello/ruby").json)
    end

    it "drives any Rack app" do
      client = Skyward::Test.client(->(env) { [200, {}, [env["PATH_INFO"]]] })

      assert_equal "/hello", client.get("/hello").body
    end
  end
end
