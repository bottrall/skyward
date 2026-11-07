# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Router do
  let(:todos) { Class.new(Skyward::API).new }

  def endpoint(verb, pattern, to, api: todos)
    Skyward::API::Router::Endpoint.new(verb:, pattern:, api:, to:, keywords: [], returns: [])
  end

  let(:router) do
    Skyward::API::Router.new(
      [
        endpoint("GET", ["", "todos"], :index),
        endpoint("GET", ["", "todos", :id], :show),
        endpoint("POST", ["", "todos", :id, "complete"], :complete)
      ]
    )
  end

  def found(to, api: todos, **params)
    Skyward::API::Router::Match.new(api:, to:, params:)
  end

  describe "#match" do
    it "matches a route by its method and path" do
      assert_equal found(:complete, id: "42"), router.match("POST", "/todos/42/complete")
    end

    it "matches a root route" do
      routes = Skyward::API::Router.new([endpoint("GET", ["", ""], :index)])

      assert_equal found(:index), routes.match("GET", "/")
    end

    it "matches HEAD to a GET route" do
      assert_equal found(:show, id: "42"), router.match("HEAD", "/todos/42")
    end

    it "tries endpoints in order" do
      other = Class.new(Skyward::API).new
      routes = Skyward::API::Router.new(
        [endpoint("GET", ["", :id], :show), endpoint("GET", ["", "new"], :new_form, api: other)]
      )

      assert_equal found(:show, id: "new"), routes.match("GET", "/new")
    end

    it "doesn't match another method" do
      assert_nil router.match("DELETE", "/todos/42")
    end

    it "doesn't match a path with a trailing slash the route doesn't have" do
      assert_nil router.match("GET", "/todos/")
    end

    it "doesn't match a path with more segments" do
      assert_nil router.match("GET", "/todos/42/complete")
    end

    it "doesn't match another literal segment" do
      assert_nil router.match("POST", "/todos/42/undo")
    end

    it "doesn't match an empty segment to a path parameter" do
      assert_nil router.match("POST", "/todos//complete")
    end

    it "percent-decodes a path parameter, keeping %2F inside it" do
      assert_equal found(:show, id: "a/b c"), router.match("GET", "/todos/a%2Fb%20c")
    end

    it "decodes a path parameter as UTF-8" do
      assert_equal found(:show, id: "café"), router.match("GET", "/todos/caf%C3%A9")
    end

    it "leaves a malformed escape as it is" do
      assert_equal found(:show, id: "100%zz"), router.match("GET", "/todos/100%zz")
    end
  end

  describe "#allowed" do
    it "lists the methods of every route matching the path, in order, with HEAD for GET and OPTIONS" do
      routes = Skyward::API::Router.new(
        [
          endpoint("DELETE", ["", "todos", :id], :destroy),
          endpoint("PUT", ["", "todos", :id], :replace),
          endpoint("GET", ["", "todos", "new"], :new_form),
          endpoint("GET", ["", "todos", :id], :show)
        ]
      )

      assert_equal %w[GET HEAD PUT DELETE OPTIONS], routes.allowed("/todos/new")
    end

    it "lists nothing for a path no route matches" do
      assert_empty router.allowed("/todos/42/undo")
    end

    it "lists HEAD only for a path with a GET route" do
      assert_equal %w[POST OPTIONS], router.allowed("/todos/42/complete")
    end
  end
end
