# frozen_string_literal: true

require "json"

class Skyward::API::App
  # @rbs! type response = [Integer, Hash[String, String], Array[String]]

  # @rbs @router: Skyward::API::Router

  # @rbs router: Skyward::API::Router
  # @rbs return: void
  def initialize(router)
    @router = router
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: response
  def call(env)
    verb = env["REQUEST_METHOD"]
    path = env["PATH_INFO"]
    match = @router.match(verb, path)
    status, headers, body = match ? respond(match) : unmatched(verb, @router.allowed(path))
    [status, headers, verb == "HEAD" ? [] : body]
  end

  private

  # @rbs match: Skyward::API::Router::Match
  # @rbs return: response
  def respond(match)
    json(200, { "content-type" => "application/json" }, match.api.public_send(match.to, **match.params))
  rescue StandardError
    problem(500, "Internal Server Error")
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
