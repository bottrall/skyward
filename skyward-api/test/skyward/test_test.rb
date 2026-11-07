# frozen_string_literal: true

require "test_helper"

describe Skyward::Test do
  describe ".client" do
    it "drives a Skyward app" do
      hello = Class.new(Skyward::API) do
        get "/:name", to: :greet

        def greet(name:) = { message: "Hello, #{name}" }
      end.new
      client = Skyward::Test.client(Skyward.app(logger: nil) { |app| app.mount hello, at: "/hello" })

      assert_equal({ message: "Hello, ruby" }, client.get("/hello/ruby").json)
    end

    it "drives any Rack app" do
      client = Skyward::Test.client(->(env) { [200, {}, [env["PATH_INFO"]]] })

      assert_equal "/hello", client.get("/hello").body
    end
  end
end
