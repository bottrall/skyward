# frozen_string_literal: true

# rbs_inline: enabled

# @rbs use Skyward::API::*

# The api group: requests through Skyward.app, called in-process as a Rack
# server would call it, without a server or the test client's JSON.
module Bench::Requests
  extend self

  # Bench::RoutesAPI is mounted at each, so the routes app has 200 endpoints.
  PREFIXES = (1..10).map { |number| "/v#{number}" }.freeze #: Array[String]

  TODOS = (1..100).to_h do |id|
    todo = Bench::TodosAPI::Todo.new(
      id:,
      title: "Todo #{id}",
      done: id.even?,
      due_on: Date.new(2026, 12, 1),
      tags: %w[home errands]
    )
    [id, todo]
  end.freeze #: Hash[Integer, Bench::TodosAPI::Todo]

  NEW_TODO = JSON.generate({ title: "Ship it", done: false, due_on: "2026-12-01", tags: %w[work] }) #: String

  # @rbs return: Array[Bench::Scenario]
  def scenarios
    todos = Skyward.app(logger: Discard) { |app| app.mount Bench::TodosAPI.new(todos: TODOS), at: "/todos" }
    routes = Skyward.app(logger: Discard) do |app|
      PREFIXES.each { |prefix| app.mount Bench::RoutesAPI.new, at: prefix }
    end
    [
      scenario("api.get", todos, "GET", "/todos/42", { status: 200, id: 42 }),
      scenario("api.post", todos, "POST", "/todos", { status: 201, title: "Ship it" }, body: NEW_TODO),
      scenario("api.not_found", todos, "GET", "/nope", { status: 404, title: "Not Found" }),
      scenario("api.routes.first", routes, "GET", "#{PREFIXES.first}/orders/42/lines/7", { status: 200, line_id: 7 }),
      scenario("api.routes.last", routes, "GET", "#{PREFIXES.last}/orders/42/lines/7", { status: 200, line_id: 7 }),
      scenario("api.routes.not_found", routes, "GET", "#{PREFIXES.last}/nope", { status: 404, title: "Not Found" })
    ]
  end

  # @rbs (String name, _RackApp app, String method, String path, Hash[Symbol, untyped] expected, ?body: String) -> Bench::Scenario
  def scenario(name, app, method, path, expected, body: "")
    env = env(method, path, body)
    fields = expected.keys - [:status]
    Bench::Scenario.new(
      name:,
      run: -> { call(app, env, body) },
      answer: lambda do |response|
        json = JSON.parse(response.fetch(1), symbolize_names: true)
        { status: response.fetch(0) }.merge(fields.to_h { |field| [field, json[field]] })
      end,
      expected:,
      unit: "requests",
      per_iteration: 1
    )
  end

  # @rbs method: String
  # @rbs path: String
  # @rbs body: String
  # @rbs return: Hash[String, untyped]
  def env(method, path, body)
    none = {} #: Hash[String, String]
    content = body.empty? ? none : { "CONTENT_TYPE" => "application/json", "CONTENT_LENGTH" => body.bytesize.to_s }
    {
      "REQUEST_METHOD" => method,
      "SCRIPT_NAME" => "",
      "PATH_INFO" => path,
      "QUERY_STRING" => "",
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "80",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "rack.url_scheme" => "http",
      "rack.errors" => StringIO.new,
      **content
    }.freeze
  end

  # A server gives each request an env of its own, which the app may write to.
  # @rbs (_RackApp app, Hash[String, untyped] env, String body) -> [Integer, String]
  def call(app, env, body)
    status, _headers, response = app.call(env.merge("rack.input" => StringIO.new(body)))
    [status, read(response)]
  end

  # @rbs body: untyped
  # @rbs return: String
  def read(body)
    body.enum_for(:each).to_a.join
  ensure
    body.close if body.respond_to?(:close)
  end
end
