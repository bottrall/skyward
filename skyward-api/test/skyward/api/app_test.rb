# frozen_string_literal: true

require "stringio"
require "test_helper"

describe Skyward::API::App do
  let(:todos) do
    Class.new(Skyward::API) do
      def show(id:) = { id:, title: "Ship it" }

      def fail(id:) = raise("todo #{id} is secret")

      def rename(id:, body:) = { id:, title: body }
    end.new
  end
  let(:middleware) { [] }
  let(:app) do
    string = Skyward::Types::Scalar.new(name: :string)
    id = Skyward::API::Router::Keyword.new(name: :id, source: :path, required: true, type: string)
    body = Skyward::API::Router::Keyword.new(name: :body, source: :body, required: true, type: string)
    endpoints = [
      ["GET", [id], :id, :show],
      ["DELETE", [id], :id, :destroy],
      ["GET", [id], :id, "fail", :fail],
      ["POST", [id], :id, "complete", :complete],
      ["PUT", [id, body], :id, :rename]
    ].map do |verb, keywords, *pattern, to|
      Skyward::API::Router::Endpoint.new(
        verb:,
        pattern: ["", "todos", *pattern],
        api: todos,
        to:,
        keywords:,
        returns: [],
        inputs: Skyward::API::Inputs.new(keywords, max_body_size: 10)
      )
    end
    Skyward::API::App.new(Skyward::API::Router.new(endpoints), middleware)
  end

  def request(method, path, body: nil, type: "application/json")
    input = body ? { "CONTENT_TYPE" => type, "rack.input" => StringIO.new(body) } : {}
    app.call({ "REQUEST_METHOD" => method, "PATH_INFO" => path, **input })
  end

  def problem(status, title, headers = {}, members = "")
    body = %({"type":"about:blank","title":"#{title}","status":#{status}#{members}})
    [status, { "content-type" => "application/problem+json", **headers }, [body]]
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

    it "calls the method with its inputs" do
      expected = [200, { "content-type" => "application/json" }, ['{"id":"42","title":"Done"}']]

      assert_equal expected, request("PUT", "/todos/42", body: '"Done"')
    end

    it "answers inputs that don't fit with a 422 problem listing every error" do
      errors = ',"errors":[{"at":"body","message":"expected String, got 1"}]'

      assert_equal problem(422, "Unprocessable Content", {}, errors), request("PUT", "/todos/42", body: "1")
    end

    it "answers a body over the limit with a 413 problem" do
      assert_equal problem(413, "Content Too Large"), request("PUT", "/todos/42", body: '"Ship it now"')
    end

    it "answers a body that isn't JSON with a 415 problem" do
      assert_equal problem(415, "Unsupported Media Type"), request("PUT", "/todos/42", body: "Done", type: "text/plain")
    end

    it "leaves an exception from the method to the layers outside it" do
      error = assert_raises(RuntimeError) { request("GET", "/todos/42/fail") }

      assert_equal "todo 42 is secret", error.message
    end

    it "answers a request no route matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("GET", "/todos")
    end

    it "answers OPTIONS on a path no route matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("OPTIONS", "/todos")
    end

    it "answers OPTIONS on a routed path with a 204 that lists its methods in allow" do
      assert_equal [204, { "allow" => "GET, HEAD, PUT, DELETE, OPTIONS" }, []], request("OPTIONS", "/todos/42")
    end

    it "answers a path routed only under other methods with a 405 problem that lists them in allow" do
      assert_equal problem(405, "Method Not Allowed", "allow" => "POST, OPTIONS"), request("GET", "/todos/42/complete")
    end

    it "answers HEAD with the GET route's status and headers and an empty body" do
      assert_equal [200, { "content-type" => "application/json" }, []], request("HEAD", "/todos/42")
    end

    it "answers HEAD on a path no route matches with a 404 and an empty body" do
      assert_equal [404, { "content-type" => "application/problem+json" }, []], request("HEAD", "/todos")
    end

    it "answers HEAD on a path routed only under other methods with a 405 and an empty body" do
      expected = [405, { "content-type" => "application/problem+json", "allow" => "POST, OPTIONS" }, []]

      assert_equal expected, request("HEAD", "/todos/42/complete")
    end
  end
end
