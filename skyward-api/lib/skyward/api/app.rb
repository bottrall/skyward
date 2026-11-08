# frozen_string_literal: true

require "json"

class Skyward::API::App
  # @rbs! type response = [Integer, Hash[String, String], Array[String]]

  INPUT_TITLES = { 413 => "Content Too Large", 415 => "Unsupported Media Type" }.freeze #: Hash[Integer, String]

  Document = Data.define(
    :type, #: String
    :body #: String
  )

  # @rbs @router: Skyward::API::Router
  # @rbs @static: Skyward::API::Static
  # @rbs @stack: Skyward::API::_RackApp
  # @rbs @documents: Hash[String, Document]

  # @rbs router: Skyward::API::Router
  # @rbs static: Skyward::API::Static
  # @rbs middleware: Array[Skyward::API::Builder::Use]
  # @rbs documents: Hash[String, Document]
  # @rbs return: void
  def initialize(router, static, middleware, documents)
    @router = router
    @static = static
    @documents = documents
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
    # Boot refuses a route or a file at a document's path, but a path parameter can still match it, so it comes first.
    status, headers, body = served(verb, path) || routed(env, verb, path)
    [status, headers, verb == "HEAD" ? dropped(body) : body]
  end

  # @rbs verb: String
  # @rbs path: String
  # @rbs return: response?
  def served(verb, path)
    document = @documents[path]
    return unless document && %w[GET HEAD].include?(verb)

    [200, { "content-type" => document.type }, [document.body]]
  end

  # @rbs env: Hash[String, untyped]
  # @rbs verb: String
  # @rbs path: String
  # @rbs return: Skyward::rack
  def routed(env, verb, path)
    match = @router.match(verb, path)
    match ? respond(match, env) : @static.call(env) || unmatched(verb, @router.allowed(path))
  end

  # @rbs match: Skyward::API::Router::Match
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::rack
  def respond(match, env)
    inputs = match.inputs.call(env, match.params)
    case inputs
    when Skyward::API::Coercer::Ok then match.serializer.call(match.api.public_send(match.to, **inputs.value))
    when Skyward::API::Coercer::Invalid then problem(422, "Unprocessable Content", errors: inputs.errors.map(&:to_h))
    when :content_too_large then problem(413, INPUT_TITLES.fetch(413))
    else problem(415, INPUT_TITLES.fetch(415))
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
