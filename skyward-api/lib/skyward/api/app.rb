# frozen_string_literal: true

require "json"

class Skyward::API::App
  # @rbs! type response = [Integer, Hash[String, String], Array[String]]

  # @rbs @router: Skyward::API::Router
  # @rbs @stack: Skyward::API::_RackApp

  # @rbs router: Skyward::API::Router
  # @rbs middleware: Array[Skyward::API::Builder::Use]
  # @rbs return: void
  def initialize(router, middleware)
    @router = router
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
    match = @router.match(env["REQUEST_METHOD"], env["PATH_INFO"])
    match ? respond(match) : problem(404, "Not Found")
  end

  # @rbs match: Skyward::API::Router::Match
  # @rbs return: response
  def respond(match)
    json(200, "application/json", match.api.public_send(match.to, **match.params))
  rescue StandardError
    problem(500, "Internal Server Error")
  end

  # @rbs status: Integer
  # @rbs title: String
  # @rbs return: response
  def problem(status, title)
    json(status, "application/problem+json", { type: "about:blank", title:, status: })
  end

  # @rbs status: Integer
  # @rbs content_type: String
  # @rbs value: untyped
  # @rbs return: response
  def json(status, content_type, value) = [status, { "content-type" => content_type }, [JSON.generate(value)]]
end
