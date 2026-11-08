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
  # @rbs return: Skyward::rack
  def route(env)
    verb = env["REQUEST_METHOD"]
    path = env["PATH_INFO"]
    match = @router.match(verb, path)
    status, headers, body = match ? respond(match, env) : @static.call(env) || unmatched(verb, @router.allowed(path))
    [status, headers, verb == "HEAD" ? dropped(body) : body]
  end

  # @rbs match: Skyward::API::Router::Match
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::rack
  def respond(match, env)
    inputs = match.inputs.call(env, match.params)
    case inputs
    when Skyward::API::Coercer::Ok then match.serializer.call(match.api.public_send(match.to, **inputs.value))
    when Skyward::API::Coercer::Invalid then problem(422, "Unprocessable Content", errors: inputs.errors.map(&:to_h))
    when :content_too_large then problem(413, "Content Too Large")
    else problem(415, "Unsupported Media Type")
    end
  end

  # A server closes the body it sends, so one that's never sent is closed here.
  # @rbs body: untyped
  # @rbs return: Array[String]
  def dropped(body)
    body.close if body.respond_to?(:close)
    []
  end

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
  # @rbs **members: untyped
  # @rbs return: response
  def problem(status, title, headers = {}, **members)
    body = { type: "about:blank", title:, status:, **members }
    json(status, { "content-type" => "application/problem+json", **headers }, body)
  end

  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs value: untyped
  # @rbs return: response
  def json(status, headers, value) = [status, headers, [JSON.generate(value)]]
end
