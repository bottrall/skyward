# frozen_string_literal: true

require "test_helper"

describe Skyward::API::App do
  let(:todos) do
    Class.new(Skyward::API) do
      get "/:id", to: :show
      get "/:id/fail", to: :fail

      def show(id:) = { id:, title: "Ship it" }

      def fail(id:) = raise("todo #{id} is secret")
    end.new
  end
  let(:app) do
    Skyward::API::App.new(Skyward::API::Router.new([Skyward::API::Builder::Mount.new(api: todos, at: "/todos")]))
  end

  def request(method, path)
    app.call({ "REQUEST_METHOD" => method, "PATH_INFO" => path })
  end

  def problem(status, title)
    body = %({"type":"about:blank","title":"#{title}","status":#{status}})
    [status, { "content-type" => "application/problem+json" }, [body]]
  end

  it "is frozen" do
    assert_predicate app, :frozen?
  end

  describe "#call" do
    it "calls the matched method with the path parameters and answers with its return value as JSON" do
      expected = [200, { "content-type" => "application/json" }, ['{"id":"42","title":"Ship it"}']]

      assert_equal expected, request("GET", "/todos/42")
    end

    it "answers an exception from the method with a 500 problem that doesn't reveal it" do
      assert_equal problem(500, "Internal Server Error"), request("GET", "/todos/42/fail")
    end

    it "answers a request no route matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("GET", "/todos")
    end
  end
end
