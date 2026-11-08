# frozen_string_literal: true

require "json_schemer"
require "test_helper"
# rack-cors expects the server to have loaded Rack already.
require "rack"
require "rack/cors"
require "tmpdir"
require_relative "../fixtures/boot/boot_fixtures"

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
    let(:fixtures) { File.expand_path("../fixtures/boot", __dir__) }
    let(:signatures) { File.join(fixtures, "sig") }

    let(:hello) { BootFixtures::Hello.new }
    let(:not_found) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/" } }

    it "requires a block" do
      error = assert_raises(ArgumentError) { Skyward.app }

      assert_equal "Skyward.app needs a block that mounts the app's APIs", error.message
    end

    it "returns an app that serves what the block mounts" do
      app = Skyward.app(signatures:, logger: nil) { |builder| builder.mount hello, at: "/hello" }
      statuses = ["/hello/ruby", "/ruby"].map do |path|
        app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => path }).first
      end

      assert_equal [200, 404], statuses
    end

    it "returns an app that serves the files the block declares" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "hello.txt"), "Hello")
        app = Skyward.app(signatures:, logger: nil) { |builder| builder.static "/", from: root }

        assert_equal ["Hello"], app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/hello.txt" }).last
      end
    end

    it "returns an app that keeps the endpoints it booted" do
      app = Skyward.app(signatures:, logger: nil) { |builder| builder.mount hello, at: "/hello" }

      assert_equal([["GET", :greet]], app.endpoints.map { |endpoint| [endpoint.verb, endpoint.to] })
    end

    it "freezes the builder once the block returns" do
      kept = nil
      Skyward.app(signatures:, logger: nil) { |builder| kept = builder }

      assert_predicate kept, :frozen?
    end

    it "reads signatures from sig/ in the current directory by default, with Skyward::API's own" do
      app = Dir.chdir(fixtures) { Skyward.app(logger: nil) { |builder| builder.mount hello } }

      assert_equal 200, app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/ruby" }).first
    end

    it "boots the README's opening example, which has no signatures directory, and answers it" do
      response = nil
      capture_io do
        app = Dir.chdir(File.expand_path("../fixtures/hello", __dir__)) { Rack::Builder.parse_file("config.ru") }
        response = Skyward::Test.client(app).get("/hello/ruby?shout=true")
      end

      assert_equal '{"message":"HELLO, RUBY"}', response.body
    end

    it "refuses to boot a route that doesn't fit its method" do
      error = assert_raises(Skyward::BootError) do
        Skyward.app(signatures:, logger: nil) { |builder| builder.mount BootFixtures::Positional.new }
      end

      assert_match(%r{\ABootFixtures::Positional#show \(GET /:id\)\n}, error.message)
    end

    it "refuses to boot an untyped endpoint with strict: true" do
      error = assert_raises(Skyward::BootError) do
        Skyward.app(signatures:, logger: nil, strict: true) { |builder| builder.mount BootFixtures::Unsigned.new }
      end

      assert_match(%r{\ABootFixtures::Unsigned#greet \(GET /:name\)\n  It has no RBS signature}, error.message)
    end

    describe "SKYWARD_STRICT" do
      def with_strict(value)
        saved = ENV.fetch("SKYWARD_STRICT", nil)
        ENV["SKYWARD_STRICT"] = value
        yield
      ensure
        ENV["SKYWARD_STRICT"] = saved
      end

      def boot_unsigned = Skyward.app(signatures:, logger: nil) { |builder| builder.mount BootFixtures::Unsigned.new }

      it "turns strict mode on when it's 1, whatever strict: says" do
        with_strict("1") { assert_raises(Skyward::BootError) { boot_unsigned } }
      end

      it "leaves strict: as it is when it's anything else" do
        with_strict("true") { assert_kind_of Skyward::API::Application, boot_unsigned }
      end
    end

    describe "docs" do
      def client(**options)
        app = Skyward.app(signatures:, logger: nil, **options) do |builder|
          builder.mount BootFixtures::Documented.new, at: "/todos"
          builder.mount hello, at: "/hello"
        end
        Skyward::Test.client(app)
      end

      it "serves no OpenAPI document or API reference by default" do
        assert_equal [404, 404], [client.get("/openapi.json").status, client.get("/docs").status]
      end

      it "serves the app's OpenAPI document at /openapi.json with docs: true, valid against the OpenAPI 3.1 schema" do
        document = JSON.parse(client(docs: true).get("/openapi.json").body)
        errors = JSONSchemer.openapi(document).validate.map { |error| error["error"] }

        assert_equal [[], ["/todos", "/todos/{id}", "/todos/{id}/elsewhere", "/todos/{id}/export", "/hello/{name}"]],
                     [errors, document["paths"].keys]
      end

      it "titles the document API, version 0.1.0, by default" do
        assert_equal({ title: "API", version: "0.1.0" }, client(docs: true).get("/openapi.json").json[:info])
      end

      it "takes the document's info and schema names from its options" do
        json = client(
          docs: true,
          title: "Todos",
          version: "1.0.0",
          description: "Lists of things.",
          schema_names: { BootFixtures::Draft => "Draft" }
        ).get("/openapi.json").json

        assert_equal [{ title: "Todos", version: "1.0.0", description: "Lists of things." }, true],
                     [json[:info], json.dig(:components, :schemas).key?(:Draft)]
      end

      it "serves an API reference at /docs with docs: true, loading Scalar from jsDelivr by default" do
        response = client(docs: true, title: "Todos").get("/docs")
        page = Skyward::API::Docs.page(title: "Todos", scalar_url: Skyward::API::Docs::SCALAR_URL)

        assert_equal [200, "text/html; charset=utf-8", page],
                     [response.status, response.headers["content-type"], response.body]
      end

      it "loads Scalar for the API reference from scalar_url:" do
        assert_includes client(docs: true, scalar_url: "/scalar.js").get("/docs").body, '<script src="/scalar.js">'
      end

      it "refuses to boot an app whose document has a problem" do
        error = assert_raises(Skyward::BootError) do
          Skyward.app(signatures:, logger: nil, docs: true) do |builder|
            builder.mount hello, at: "/hello"
            builder.mount hello, at: "/hi"
          end
        end

        assert_match(/Its OpenAPI operation ID, BootFixtures\.Hello_greet, is/, error.message)
      end

      it "builds the document when asked, without docs: true, from the same options" do
        app = Skyward.app(signatures:, logger: nil, title: "Todos") { |builder| builder.mount hello, at: "/hello" }

        assert_equal [{ title: "Todos", version: "0.1.0" }, ["/hello/{name}"]],
                     [app.openapi[:info], app.openapi[:paths].keys]
      end

      it "boots without docs: true an app whose document has a problem, refusing only when it's asked for" do
        app = Skyward.app(signatures:, logger: nil) do |builder|
          builder.mount hello, at: "/hello"
          builder.mount hello, at: "/hi"
        end

        assert_raises(Skyward::BootError) { app.openapi }
      end
    end

    describe "inputs" do
      def client(**options)
        app = Skyward.app(signatures:, logger: nil, **options) { |builder| builder.mount BootFixtures::Todos.new }
        Skyward::Test.client(app)
      end

      let(:overhead) { '{"title":""}'.bytesize }

      it "reads a body of up to 1 MiB by default" do
        assert_equal 200, client.post("/", json: { title: "a" * (1_048_576 - overhead) }).status
      end

      it "refuses a body over 1 MiB by default" do
        assert_equal 413, client.post("/", json: { title: "a" * (1_048_576 - overhead + 1) }).status
      end

      it "refuses a body over the max_body_size it's given" do
        assert_equal 413, client(max_body_size: 10).post("/", json: { title: "Ship it" }).status
      end
    end

    describe "request:" do
      let(:client) do
        Skyward::Test.client(
          Skyward.app(signatures:, logger: nil) { |builder| builder.mount BootFixtures::Requesting.new }
        )
      end

      it "gives the endpoint the request's headers, cookies, IP and request ID" do
        headers = { "Authorization" => "Bearer abc", "X-Forwarded-For" => "203.0.113.7", "X-Request-Id" => "abc-123" }
        response = client.get("/?request=x", headers:, cookies: { "session" => "s3cret" })
        expected = { authorization: "Bearer abc", session: "s3cret", ip: "203.0.113.7", request_id: "abc-123" }

        assert_equal expected, response.json
      end
    end

    describe "providers" do
      def client(**options)
        app = Skyward.app(signatures:, logger: nil, **options) do |builder|
          builder.provide :current_user, BootFixtures::CurrentUser.new
          builder.provide :tenant, ->(request) { request.headers["x-tenant"] }
          builder.mount BootFixtures::Authenticated.new
        end
        Skyward::Test.client(app)
      end

      it "answers an endpoint behind an authentication provider with its 401, without running it" do
        response = client.get("/me")

        assert_equal [401, "Sign in first"], [response.status, response.json[:detail]]
      end

      it "gives the endpoint each provider's value for the request" do
        headers = { "Authorization" => "Bearer ada", "X-Tenant" => "acme" }

        assert_equal [{ id: 7, title: "acme Ada" }], client.get("/todos?limit=7", headers:).json
      end

      it "answers 401 rather than 422 when the query doesn't fit as well" do
        assert_equal 401, client.get("/todos?limit=x").status
      end

      it "documents a typed provider's 401 on each endpoint asking for it, and no provided name as a parameter" do
        paths = JSON.parse(client(docs: true).get("/openapi.json").body)["paths"]
        me = paths.dig("/me", "get")
        index = paths.dig("/todos", "get")

        assert_equal [%w[200 401], nil, %w[200 401 422], ["limit"]],
                     [me["responses"].keys, me["parameters"], index["responses"].keys,
                      index["parameters"].map { |parameter| parameter["name"] }]
      end
    end

    describe "answering by the return type" do
      let(:client) do
        Skyward::Test.client(
          Skyward.app(signatures:, logger: nil) do |builder|
            builder.mount BootFixtures::Responding.new
          end
        )
      end

      it "writes only the fields the return type declares" do
        assert_equal({ id: 1, name: "Ada" }, client.get("/users/1").json)
      end

      it "answers a response value with its status" do
        response = client.get("/2")

        assert_equal [404, "Todo 2 does not exist"], [response.status, response.json[:detail]]
      end

      it "answers a value that doesn't fit with a 500 that sends none of it" do
        response = client.get("/users/1/todo")

        assert_equal [500, false], [response.status, response.body.include?("Ada")]
      end

      describe "with a Rack triple" do
        let(:client) do
          Skyward::Test.client(
            Skyward.app(signatures:, logger: nil) do |builder|
              builder.mount BootFixtures::Racking.new
            end
          )
        end

        it "streams the body it's given, with its status, its headers and the request ID" do
          response = client.get("/stream", headers: { "X-Request-Id" => "abc-123" })
          headers = { "content-type" => "text/plain", "x-request-id" => "abc-123" }

          assert_equal [200, headers, "first\nsecond\n"], [response.status, response.headers, response.body]
        end

        it "answers an Array of three items as JSON when the return type is an Array" do
          response = client.get("/letters")

          assert_equal ["application/json", %w[a b c]], [response.headers["content-type"], response.json]
        end
      end
    end

    it "runs the app inside the middleware the block uses, inside the request ID" do
      app = Skyward.app(signatures:, logger: nil) do |builder|
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
        app = Skyward.app(signatures:) { |builder| builder.mount hello, at: "/hello" }
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
      out, = capture_io { Skyward.app(signatures:, logger:) { |builder| builder.mount hello }.call(not_found) }

      assert_empty out
      assert_equal([404], logger.lines.map { |line| JSON.parse(line).fetch("status") })
    end

    it "logs nothing given a nil logger" do
      out, = capture_io { Skyward.app(signatures:, logger: nil) { |builder| builder.mount hello }.call(not_found) }

      assert_empty out
    end

    it "logs a request the middleware answers" do
      logger = Struct.new(:lines) { def info(message) = lines << message }.new([])
      app = Skyward.app(signatures:, logger:) do |builder|
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
      app = Skyward.app(signatures:, logger: nil) { |builder| builder.mount hello, at: "/hello" }
      status, headers, _body = app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => "/ruby" })

      assert_equal 404, status
      assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, headers["x-request-id"])
    end

    describe "when something raises" do
      let(:failing) { BootFixtures::Failing.new }
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
        app = Skyward.app(signatures:, logger:, on_error:) do |builder|
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

      it "answers a 500 for a provider that raises" do
        app = Skyward.app(signatures:, logger:) do |builder|
          builder.provide :current_user, ->(_request) { raise "sessions are down" }
          builder.mount BootFixtures::Authenticated.new
        end
        response = with_env(nil) { Skyward::Test.client(app).get("/me", headers: { "X-Request-Id" => "abc-123" }) }
        answered = [response.status, response.json[:request_id], lines.first[:message]]

        assert_equal [500, "abc-123", "sessions are down"], answered
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

  describe "the response helpers" do
    let(:headers) { { "www-authenticate" => "Bearer" } }

    def fields(value, *names) = [value.class, *names.map { |name| value.public_send(name) }, value.frozen?]

    it ".bad_request, .unauthorized and .forbidden make a frozen problem with its detail and headers" do
      made = [Skyward.bad_request("Bad", headers:), Skyward.unauthorized("Sign in first"),
              Skyward.forbidden("Not yours")]

      assert_equal(
        [[Skyward::BadRequest, "Bad", headers, true], [Skyward::Unauthorized, "Sign in first", {}, true],
         [Skyward::Forbidden, "Not yours", {}, true]],
        made.map { |value| fields(value, :detail, :headers) }
      )
    end

    describe ".redirect" do
      it "raises for a status that isn't a redirect's" do
        error = assert_raises(ArgumentError) { Skyward.redirect("/todos", status: 200) }

        assert_equal "A redirect's status must be one of 301, 302, 303, 307, 308, not 200", error.message
      end

      it "raises for a location with a carriage return or a line feed" do
        messages = ["/\rx", "/\nx"].map { |to| assert_raises(ArgumentError) { Skyward.redirect(to) }.message }

        assert_equal(
          ["A redirect's location can't contain a line break: \"/\\rx\"",
           "A redirect's location can't contain a line break: \"/\\nx\""],
          messages
        )
      end

      it "makes a frozen Redirect, with a 303 unless it's given a status" do
        made = [Skyward.redirect("/todos"), Skyward.redirect("/todos/1", status: 308, headers:)]

        assert_equal(
          [[Skyward::Redirect, "/todos", 303, {}, true], [Skyward::Redirect, "/todos/1", 308, headers, true]],
          made.map { |value| fields(value, :to, :status, :headers) }
        )
      end
    end
  end
end
