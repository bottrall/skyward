# frozen_string_literal: true

class Skyward::API::RequestId
  # Visible ASCII only, so a client can't put a space or a line break in the logs.
  VALID = /\A[!-~]{1,200}\z/ #: Regexp

  # @rbs @app: Skyward::API::_RackApp
  # @rbs @generate: ^() -> String

  # @rbs (Skyward::API::_RackApp app, generate: ^() -> String) -> void
  def initialize(app, generate:)
    @app = app
    @generate = generate
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env)
    incoming = env["HTTP_X_REQUEST_ID"]
    # Matched as binary, because Regexp#match? raises on a String that isn't valid UTF-8.
    id = VALID.match?(incoming&.b) ? incoming : @generate.call
    status, headers, body = @app.call(env.merge("skyward.request_id" => id))
    [status, headers.merge("x-request-id" => id), body]
  end
end
