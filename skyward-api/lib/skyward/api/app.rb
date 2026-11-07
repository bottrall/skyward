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
    match = @router.match(env["REQUEST_METHOD"], env["PATH_INFO"])
    match ? respond(match) : problem(404, "Not Found")
  end

  private

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
