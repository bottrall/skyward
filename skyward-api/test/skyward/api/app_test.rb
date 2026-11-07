# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::API::App do
  let(:root) { Dir.mktmpdir }
  let(:todos) do
    Class.new(Skyward::API) do
      def show(id:) = { id:, title: "Ship it" }

      def fail(id:) = raise("todo #{id} is secret")
    end.new
  end
  let(:middleware) { [] }
  let(:app) do
    endpoints = [
      ["GET", :id, :show],
      ["DELETE", :id, :destroy],
      ["GET", :id, "fail", :fail],
      ["POST", :id, "complete", :complete]
    ].map do |verb, *pattern, to|
      Skyward::API::Router::Endpoint.new(
        verb:,
        pattern: ["", "todos", *pattern],
        api: todos,
        to:,
        keywords: [],
        returns: []
      )
    end
    static = Skyward::API::Static.new([Skyward::API::Builder::Static.new(prefix: "/", from: File.join(root, "public"))])
    Skyward::API::App.new(Skyward::API::Router.new(endpoints), static, middleware)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "public/todos/7"))
    File.write(File.join(root, "public/todos/42"), "A static todo")
    File.write(File.join(root, "public/todos/7/complete"), "Done")
    File.write(File.join(root, "public/hello.txt"), "Hello")
    File.write(File.join(root, "secret.txt"), "hunter2")
  end

  after { FileUtils.remove_entry(root) }

  def request(method, path)
    app.call({ "REQUEST_METHOD" => method, "PATH_INFO" => path })
  end

  def problem(status, title, headers = {})
    body = %({"type":"about:blank","title":"#{title}","status":#{status}})
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

    it "leaves an exception from the method to the layers outside it" do
      error = assert_raises(RuntimeError) { request("GET", "/todos/42/fail") }

      assert_equal "todo 42 is secret", error.message
    end

    it "serves a static file when no route matches" do
      assert_equal ["Hello"], request("GET", "/hello.txt").last
    end

    it "lets a route take precedence over a static file" do
      assert_equal ['{"id":"42","title":"Ship it"}'], request("GET", "/todos/42").last
    end

    it "serves a static file at a path routed only under other methods" do
      assert_equal ["Done"], request("GET", "/todos/7/complete").last
    end

    it "answers a path that climbs out of a static directory with a 404 problem" do
      responses = ["/../secret.txt", "/%2e%2e/secret.txt"].map { |path| request("GET", path) }

      assert_equal [problem(404, "Not Found")] * 2, responses
    end

    it "answers a request no route or file matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("GET", "/todos")
    end

    it "answers OPTIONS on a path no route matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("OPTIONS", "/todos")
    end

    it "answers OPTIONS on a routed path with a 204 that lists its methods in allow" do
      assert_equal [204, { "allow" => "GET, HEAD, DELETE, OPTIONS" }, []], request("OPTIONS", "/todos/42")
    end

    it "answers a path routed only under other methods with a 405 problem that lists them in allow" do
      assert_equal problem(405, "Method Not Allowed", "allow" => "POST, OPTIONS"), request("GET", "/todos/42/complete")
    end

    it "answers a method other than GET or HEAD on a static file's path as if there were no file" do
      assert_equal problem(405, "Method Not Allowed", "allow" => "POST, OPTIONS"), request("PUT", "/todos/7/complete")
    end

    it "answers HEAD with the GET route's status and headers and an empty body" do
      assert_equal [200, { "content-type" => "application/json" }, []], request("HEAD", "/todos/42")
    end

    it "answers HEAD on a static file with its status and headers and an empty body" do
      status, headers, body = request("HEAD", "/hello.txt")

      assert_equal [200, "5", []], [status, headers["content-length"], body]
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
