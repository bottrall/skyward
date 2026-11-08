# frozen_string_literal: true

require "stringio"
require "test_helper"
require "tmpdir"

describe Skyward::API::App do
  let(:root) { Dir.mktmpdir }
  let(:todos) do
    Class.new(Skyward::API) do
      def show(id:) = { id:, title: "Ship it" }

      def fail(id:) = raise("todo #{id} is secret")

      def rename(id:, body:) = { id: "#{id}: #{body}" }
    end.new
  end
  let(:middleware) { [] }
  let(:documents) { {} }
  let(:returns) do
    id = Skyward::Types::Field.new(name: :id, type: Skyward::Types::Scalar.new(name: :string), required: true)
    [Skyward::Types::Record.new(fields: [id])]
  end
  let(:app) do
    serializer = Skyward::API::Serializer.new(returns, label: "Todos#show")
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
        label: "Todos##{to}",
        summary: nil,
        description: nil,
        keywords:,
        returns:,
        inputs: Skyward::API::Inputs.new(keywords, max_body_size: 10),
        serializer:
      )
    end
    static = Skyward::API::Static.new([Skyward::API::Builder::Static.new(prefix: "/", from: File.join(root, "public"))])
    Skyward::API::App.new(Skyward::API::Router.new(endpoints), static, middleware, documents)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "public/todos/7"))
    File.write(File.join(root, "public/todos/42"), "A static todo")
    File.write(File.join(root, "public/todos/7/complete"), "Done")
    File.write(File.join(root, "public/hello.txt"), "Hello")
    File.write(File.join(root, "secret.txt"), "hunter2")
  end

  after { FileUtils.remove_entry(root) }

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

    describe "with documents" do
      let(:openapi) { '{"openapi":"3.1.0"}' }
      let(:documents) do
        {
          "/openapi.json" => Skyward::API::App::Document.new(type: "application/json", body: openapi),
          "/docs" => Skyward::API::App::Document.new(type: "text/html; charset=utf-8", body: "<!doctype html>")
        }
      end

      it "serves each at its path with its content type" do
        expected = [
          [200, { "content-type" => "application/json" }, [openapi]],
          [200, { "content-type" => "text/html; charset=utf-8" }, ["<!doctype html>"]]
        ]

        assert_equal expected, [request("GET", "/openapi.json"), request("GET", "/docs")]
      end

      it "serves one before a static file at its path" do
        File.write(File.join(root, "public/openapi.json"), "{}")

        assert_equal [openapi], request("GET", "/openapi.json").last
      end

      it "answers HEAD with its status and headers and an empty body" do
        assert_equal [200, { "content-type" => "application/json" }, []], request("HEAD", "/openapi.json")
      end

      it "answers a method other than GET or HEAD as if there were no document" do
        assert_equal problem(404, "Not Found"), request("POST", "/openapi.json")
      end

      it "leaves every other path to the routes" do
        assert_equal ['{"id":"42"}'], request("GET", "/todos/42").last
      end
    end

    it "serves no document without one" do
      assert_equal problem(404, "Not Found"), request("GET", "/openapi.json")
    end

    it "calls the matched method with the path parameters and answers with its serializer's response" do
      expected = [200, { "content-type" => "application/json" }, ['{"id":"42"}']]

      assert_equal expected, request("GET", "/todos/42")
    end

    it "calls the method with its inputs" do
      expected = [200, { "content-type" => "application/json" }, ['{"id":"42: Done"}']]

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

    it "serves a static file when no route matches" do
      assert_equal ["Hello"], request("GET", "/hello.txt").last
    end

    it "lets a route take precedence over a static file" do
      assert_equal ['{"id":"42"}'], request("GET", "/todos/42").last
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
      assert_equal [204, { "allow" => "GET, HEAD, PUT, DELETE, OPTIONS" }, []], request("OPTIONS", "/todos/42")
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

    describe "when the method returns a Rack triple" do
      let(:body) do
        Class.new do
          attr_reader :closed

          def each = yield("Hello")

          def close
            @closed = true
          end
        end.new
      end
      let(:todos) do
        sent = body
        Class.new(Skyward::API) { define_method(:show) { |id:| [200, { "x-todo" => id }, sent] } }.new
      end
      let(:returns) { [Skyward::API::Router::Rack.new] }

      it "answers it with its body untouched" do
        assert_equal [200, { "x-todo" => "42" }, body], request("GET", "/todos/42")
      end

      it "closes the body it drops for HEAD" do
        response = request("HEAD", "/todos/42")

        assert_equal [[], true], [response.last, body.closed]
      end
    end
  end
end
