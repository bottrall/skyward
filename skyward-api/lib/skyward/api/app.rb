# frozen_string_literal: true

require "json"

class Skyward::API::App
  # @rbs! type response = [Integer, Hash[String, String], Array[String]]

  # @rbs @router: Skyward::API::Router
  # @rbs @static: Skyward::API::Static
  # @rbs @stack: Skyward::API::_RackApp

  # @rbs router: Skyward::API::Router
  # @rbs static: Skyward::API::Static
  # @rbs middleware: Array[Skyward::API::Builder::Use]
  # @rbs return: void
  def initialize(router, static, middleware)
    @router = router
    @static = static
    innermost = method(:route) #: Skyward::API::_RackApp
    @stack = middleware.reverse.reduce(innermost) do |app, use|
      use.middleware.new(app, *use.args, **use.kwargs, &use.block)
    end
    # Only the app is frozen, not the middleware: some keep state of their
    # own, like the logger rack-cors picks on its first request.
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env) = @stack.call(env)

  private

  # @rbs env: Hash[String, untyped]
  # @rbs return: response
  def route(env)
    verb = env["REQUEST_METHOD"]
    path = env["PATH_INFO"]
    match = @router.match(verb, path)
    status, headers, body = match ? respond(match) : @static.call(env) || unmatched(verb, @router.allowed(path))
    [status, headers, verb == "HEAD" ? [] : body]
  end

  # @rbs match: Skyward::API::Router::Match
  # @rbs return: response
  def respond(match) = match.serializer.call(match.api.public_send(match.to, **match.params))

  # @rbs verb: String
  # @rbs allowed: Array[String]
  # @rbs return: response
  def unmatched(verb, allowed)
    return problem(404, "Not Found") if allowed.empty?

    allow = { "allow" => allowed.join(", ") }
    verb == "OPTIONS" ? [204, allow, []] : problem(405, "Method Not Allowed", allow)
  end

  # @rbs status: Integer
  # @rbs title: String
  # @rbs headers: Hash[String, String]
  # @rbs return: response
  def problem(status, title, headers = {})
    json(status, { "content-type" => "application/problem+json", **headers }, { type: "about:blank", title:, status: })
  end

  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs value: untyped
  # @rbs return: response
  def json(status, headers, value) = [status, headers, [JSON.generate(value)]]
end
