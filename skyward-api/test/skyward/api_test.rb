# frozen_string_literal: true

require "test_helper"

describe Skyward::API do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "gives every API class the route declarations" do
    assert_kind_of Skyward::API::Declarations, Skyward::API
  end
end

describe Skyward do
  describe ".app" do
    let(:hello) do
      Class.new(Skyward::API) do
        get "/:name", to: :greet

        def greet(name:) = { message: "Hello, #{name}" }
      end.new
    end

    it "requires a block" do
      error = assert_raises(ArgumentError) { Skyward.app }

      assert_equal "Skyward.app needs a block that mounts the app's APIs", error.message
    end

    it "returns an app that serves what the block mounts" do
      app = Skyward.app { |builder| builder.mount hello, at: "/hello" }
      statuses = ["/hello/ruby", "/ruby"].map do |path|
        app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => path }).first
      end

      assert_equal [200, 404], statuses
    end

    it "freezes the builder once the block returns" do
      kept = nil
      Skyward.app { |builder| kept = builder }

      assert_predicate kept, :frozen?
    end

    it "answers even a 404 with a random UUID request ID" do
      app = Skyward.app { |builder| builder.mount hello, at: "/hello" }
      status, headers, _body = app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/ruby" })

      assert_equal 404, status
      assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, headers["x-request-id"])
    end
  end
end
