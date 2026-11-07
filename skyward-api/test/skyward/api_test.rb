# frozen_string_literal: true

require "test_helper"
# rack-cors expects the server to have loaded Rack already.
require "rack"
require "rack/cors"

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
    let(:not_found) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/" } }

    it "requires a block" do
      error = assert_raises(ArgumentError) { Skyward.app }

      assert_equal "Skyward.app needs a block that mounts the app's APIs", error.message
    end

    it "returns an app that serves what the block mounts" do
      app = Skyward.app(logger: nil) { |builder| builder.mount hello, at: "/hello" }
      statuses = ["/hello/ruby", "/ruby"].map do |path|
        app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => path }).first
      end

      assert_equal [200, 404], statuses
    end

    it "freezes the builder once the block returns" do
      kept = nil
      Skyward.app(logger: nil) { |builder| kept = builder }

      assert_predicate kept, :frozen?
    end

    it "runs the app inside the middleware the block uses, inside the request ID" do
      app = Skyward.app(logger: nil) do |builder|
        builder.use Rack::Cors do
          allow do
            origins "https://example.com"
            resource "*", methods: %i[get]
          end
        end
        builder.mount hello, at: "/hello"
      end
      headers = { "Origin" => "https://example.com", "Access-Control-Request-Method" => "GET" }
      response = Skyward::Test.client(app).options("/hello/ruby", headers:)

      assert_equal [200, "https://example.com"], [response.status, response.headers["access-control-allow-origin"]]
      assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, response.headers["x-request-id"])
    end

    it "logs each request to standard output by default, as a JSON line with its request ID" do
      responses = nil
      out, = capture_io do
        app = Skyward.app { |builder| builder.mount hello, at: "/hello" }
        responses = ["/hello/ruby", "/ruby"].map { |path| app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => path }) }
      end
      lines = out.lines.map { |line| JSON.parse(line, symbolize_names: true) }
      ids = responses.map { |(_status, headers)| headers["x-request-id"] }
      expected = [[200, "/hello/ruby", ids[0]], [404, "/ruby", ids[1]]]

      assert_equal(expected, lines.map { |line| line.values_at(:status, :path, :request_id) })
      assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/, lines.first[:time])
      assert_kind_of Float, lines.first[:duration_ms]
    end

    it "logs to the logger it's given instead" do
      logger = Struct.new(:lines) { def info(message) = lines << message }.new([])
      out, = capture_io { Skyward.app(logger:) { |builder| builder.mount hello }.call(not_found) }

      assert_empty out
      assert_equal([404], logger.lines.map { |line| JSON.parse(line).fetch("status") })
    end

    it "logs nothing given a nil logger" do
      out, = capture_io { Skyward.app(logger: nil) { |builder| builder.mount hello }.call(not_found) }

      assert_empty out
    end

    it "logs a request the middleware answers" do
      logger = Struct.new(:lines) { def info(message) = lines << message }.new([])
      app = Skyward.app(logger:) do |builder|
        builder.use Rack::Cors do
          allow do
            origins "https://example.com"
            resource "*", methods: %i[get]
          end
        end
        builder.mount hello, at: "/hello"
      end
      headers = { "Origin" => "https://example.com", "Access-Control-Request-Method" => "GET" }
      Skyward::Test.client(app).options("/hello/ruby", headers:)
      line = JSON.parse(logger.lines.first, symbolize_names: true)

      assert_equal({ method: "OPTIONS", path: "/hello/ruby", status: 200 }, line.slice(:method, :path, :status))
    end

    it "answers even a 404 with a random UUID request ID" do
      app = Skyward.app(logger: nil) { |builder| builder.mount hello, at: "/hello" }
      status, headers, _body = app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/ruby" })

      assert_equal 404, status
      assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, headers["x-request-id"])
    end

    describe "when something raises" do
      let(:failing) do
        Class.new(Skyward::API) do
          get "/", to: :fail

          def fail = raise("todo 42 is secret")
        end.new
      end
      let(:lines) { [] }
      let(:logger) do
        Struct.new(:lines) do
          def info(message) = lines << JSON.parse(message, symbolize_names: true)
        end.new(lines)
      end

      def with_env(rack_env, app_env = nil)
        saved = ENV.slice("RACK_ENV", "APP_ENV")
        ENV.update("RACK_ENV" => rack_env, "APP_ENV" => app_env)
        yield
      ensure
        ENV.update("RACK_ENV" => saved["RACK_ENV"], "APP_ENV" => saved["APP_ENV"])
      end

      def get_failing(on_error: nil)
        app = Skyward.app(logger:, on_error:) do |builder|
          yield builder if block_given?
          builder.mount failing
        end
        Skyward::Test.client(app).get("/", headers: { "X-Request-Id" => "abc-123" })
      end

      it "answers a 500 with the request ID, and logs the exception before the request" do
        response = with_env(nil) { get_failing }
        problem = { type: "about:blank", title: "Internal Server Error", status: 500, request_id: "abc-123" }
        logged = lines.map { |line| line.values_at(:level, :status, :request_id) }

        assert_equal [problem, [["error", nil, "abc-123"], [nil, 500, "abc-123"]]], [response.json, logged]
      end

      it "reports the exception to the hook it's given" do
        reported = []
        on_error = ->(exception, env) { reported << [exception.message, env["skyward.request_id"]] }
        with_env(nil) { get_failing(on_error:) }

        assert_equal [["todo 42 is secret", "abc-123"]], reported
      end

      it "answers a 500 for middleware that raises" do
        raising = Class.new do
          def initialize(_app) = nil

          def call(_env) = raise("middleware broke")
        end
        response = with_env(nil) { get_failing { |builder| builder.use raising } }
        answered = [response.status, response.json[:request_id], lines.first[:message]]

        assert_equal [500, "abc-123", "middleware broke"], answered
      end

      it "adds the backtrace when RACK_ENV is development" do
        assert_kind_of Array, with_env("development") { get_failing }.json[:backtrace]
      end

      it "adds the backtrace when APP_ENV is development and RACK_ENV isn't set" do
        assert_kind_of Array, with_env(nil, "development") { get_failing }.json[:backtrace]
      end

      it "leaves out the backtrace when RACK_ENV is anything else, whatever APP_ENV says" do
        refute_includes with_env("production", "development") { get_failing }.json.keys, :backtrace
      end
    end
  end
end
