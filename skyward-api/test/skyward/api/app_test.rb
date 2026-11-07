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
  let(:middleware) { [] }
  let(:app) do
    router = Skyward::API::Router.new([Skyward::API::Builder::Mount.new(api: todos, at: "/todos")])
    Skyward::API::App.new(router, middleware)
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
    describe "with middleware" do
      def use(middleware, *args, **kwargs, &block)
        Skyward::API::Builder::Use.new(middleware:, args:, kwargs:, block:)
      end

      describe "that passes the request on" do
        let(:trail) { [] }
        let(:middleware) do
          tracer = Class.new do
            def initialize(app, name, trail:)
              @app = app
              @name = name
              @trail = trail
            end

            def call(env)
              @trail << "#{@name} in"
              @app.call(env).tap { @trail << "#{@name} out" }
            end
          end
          [use(tracer, "first", trail:), use(tracer, "second", trail:)]
        end

        it "runs it around the routes, the first outermost" do
          status = request("GET", "/todos/42").first

          assert_equal [200, ["first in", "second in", "second out", "first out"]], [status, trail]
        end
      end

      describe "that answers itself" do
        let(:middleware) do
          echo = Class.new do
            def initialize(_app, *args, **kwargs)
              @answer = [200, {}, [args, kwargs, yield]]
            end

            def call(_env) = @answer
          end
          [use(echo, "/assets", max_age: 60) { :configured }]
        end

        it "gives it the arguments and block it was used with" do
          assert_equal [200, {}, [["/assets"], { max_age: 60 }, :configured]], request("GET", "/todos/42")
        end
      end
    end

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
