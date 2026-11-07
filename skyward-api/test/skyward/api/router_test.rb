# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Router do
  let(:todos_class) do
    Class.new(Skyward::API) do
      get "/", to: :index
      get "/:id", to: :show
      post "/:id/complete", to: :complete
    end
  end
  let(:todos) { todos_class.new }

  def router(*mounts)
    Skyward::API::Router.new(mounts.map { |api, at| Skyward::API::Builder::Mount.new(api:, at:) })
  end

  def found(api, to, **params)
    Skyward::API::Router::Match.new(api:, to:, params:)
  end

  describe ".new" do
    it "reads the routes of each mounted object's own class" do
      api = Class.new(todos_class) { get "/:id/history", to: :history }.new

      assert_equal found(api, :history, id: "42"), router([api, "/todos"]).match("GET", "/todos/42/history")
    end

    it "reads the routes once, when it's built" do
      routes = router([todos, "/todos"])
      todos_class.delete "/:id", to: :destroy

      assert_nil routes.match("DELETE", "/todos/42")
    end

    it "serves one object at each prefix it's mounted at" do
      routes = router([todos, "/todos"], [todos, "/tasks"])

      assert_equal [found(todos, :index)] * 2, [routes.match("GET", "/todos"), routes.match("GET", "/tasks")]
    end

    it "joins the prefix to a route's path with one slash" do
      assert_equal found(todos, :complete, id: "42"), router([todos, "/todos"]).match("POST", "/todos/42/complete")
    end

    it "joins the prefix to a root route without a trailing slash" do
      assert_equal found(todos, :index), router([todos, "/todos"]).match("GET", "/todos")
    end

    it "serves a route mounted at / at its own path" do
      assert_equal found(todos, :show, id: "42"), router([todos, "/"]).match("GET", "/42")
    end

    it "serves a root route mounted at / at /" do
      assert_equal found(todos, :index), router([todos, "/"]).match("GET", "/")
    end

    it "drops a trailing slash from the prefix and the route's path" do
      api = Class.new(Skyward::API) { get "/done/", to: :done }.new

      assert_equal found(api, :done), router([api, "/todos/"]).match("GET", "/todos/done")
    end
  end

  describe "#match" do
    it "tries mounts in the order they're mounted" do
      other = todos_class.new

      assert_equal found(todos, :index), router([todos, "/todos"], [other, "/todos"]).match("GET", "/todos")
    end

    it "tries a class's routes in the order they're declared" do
      api = Class.new(Skyward::API) do
        get "/:id", to: :show
        get "/new", to: :new_form
      end.new

      assert_equal found(api, :show, id: "new"), router([api, "/"]).match("GET", "/new")
    end

    it "doesn't match another method" do
      assert_nil router([todos, "/todos"]).match("DELETE", "/todos/42")
    end

    it "doesn't match a path with a trailing slash the route doesn't have" do
      assert_nil router([todos, "/todos"]).match("GET", "/todos/")
    end

    it "doesn't match a path with more segments" do
      assert_nil router([todos, "/todos"]).match("GET", "/todos/42/complete")
    end

    it "doesn't match another literal segment" do
      assert_nil router([todos, "/todos"]).match("POST", "/todos/42/undo")
    end

    it "doesn't match an empty segment to a path parameter" do
      assert_nil router([todos, "/todos"]).match("POST", "/todos//complete")
    end

    it "percent-decodes a path parameter, keeping %2F inside it" do
      assert_equal found(todos, :show, id: "a/b c"), router([todos, "/todos"]).match("GET", "/todos/a%2Fb%20c")
    end

    it "decodes a path parameter as UTF-8" do
      assert_equal found(todos, :show, id: "café"), router([todos, "/todos"]).match("GET", "/todos/caf%C3%A9")
    end

    it "leaves a malformed escape as it is" do
      assert_equal found(todos, :show, id: "100%zz"), router([todos, "/todos"]).match("GET", "/todos/100%zz")
    end
  end
end
