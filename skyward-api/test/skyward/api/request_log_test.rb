# frozen_string_literal: true

require "test_helper"

describe Skyward::API::RequestLog do
  let(:lines) { [] }
  let(:logger) { Struct.new(:lines) { def info(message) = lines << message }.new(lines) }
  let(:readings) { [1000.0, 1012.3456] }

  def log(app)
    Skyward::API::RequestLog.new(
      app,
      logger:,
      now: -> { Time.new(2026, 11, 7, 23, 4, 5.678r, "+10:00") },
      clock_ms: -> { readings.shift }
    )
  end

  def request(app, **env)
    defaults = { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/todos/42", "skyward.request_id" => "abc-123" }
    log(app).call(defaults.merge(env))
  end

  def logged = lines.map { |line| JSON.parse(line, symbolize_names: true) }

  it "is frozen" do
    assert_predicate log(->(_env) { [204, {}, []] }), :frozen?
  end

  describe "#call" do
    it "returns the app's response and logs it as one JSON line" do
      response = [200, { "content-type" => "application/json" }, ['{"id":"42"}']]

      assert_equal response, request(->(_env) { response })
      expected = {
        time: "2026-11-07T13:04:05.678Z",
        method: "GET",
        path: "/todos/42",
        status: 200,
        duration_ms: 12.35,
        request_id: "abc-123"
      }

      assert_equal [expected], logged
    end

    it "logs the path with the prefix the app is mounted under and without the query string" do
      request(->(_env) { [200, {}, []] }, "SCRIPT_NAME" => "/api", "QUERY_STRING" => "token=secret")

      assert_equal "/api/todos/42", logged.first[:path]
      refute_includes lines.first, "secret"
    end

    it "logs the method and path the request arrived with, even if the app rewrites them" do
      rewrite = lambda do |env|
        env["REQUEST_METHOD"] = "DELETE"
        env["PATH_INFO"] = "/elsewhere"
        [204, {}, []]
      end
      request(rewrite)

      assert_equal({ method: "GET", path: "/todos/42" }, logged.first.slice(:method, :path))
    end

    it "logs a path that isn't valid UTF-8 with the invalid bytes replaced" do
      response = [404, {}, []]

      assert_equal response, request(->(_env) { response }, "PATH_INFO" => "/caf\xE9".b)
      assert_equal "/caf�", logged.first[:path]
    end

    it "logs a 404" do
      request(->(_env) { [404, { "content-type" => "application/problem+json" }, ["{}"]] }, "PATH_INFO" => "/nowhere")

      assert_equal({ path: "/nowhere", status: 404 }, logged.first.slice(:path, :status))
    end

    it "logs a request answered by middleware that never reaches an endpoint" do
      endpoint = ->(_env) { flunk "the middleware let the request through" }
      middleware = ->(env) { env.key?("HTTP_AUTHORIZATION") ? endpoint.call(env) : [401, {}, []] }
      request(middleware, "REQUEST_METHOD" => "DELETE")

      assert_equal({ method: "DELETE", status: 401 }, logged.first.slice(:method, :status))
    end
  end
end
