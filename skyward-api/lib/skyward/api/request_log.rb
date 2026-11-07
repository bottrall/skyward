# frozen_string_literal: true

require "json"
# Time#iso8601 is core only from Ruby 3.4.
require "time"

class Skyward::API::RequestLog
  # @rbs @app: Skyward::API::_RackApp
  # @rbs @logger: Skyward::API::_Logger
  # @rbs @now: ^() -> Time
  # @rbs @clock_ms: ^() -> Float

  # @rbs (Skyward::API::_RackApp app, logger: Skyward::API::_Logger, now: ^() -> Time, clock_ms: ^() -> Float) -> void
  def initialize(app, logger:, now:, clock_ms:)
    @app = app
    @logger = logger
    @now = now
    @clock_ms = clock_ms
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env)
    time = @now.call.getutc.iso8601(3)
    # Read before the app runs, because middleware can rewrite the env in place.
    method = env["REQUEST_METHOD"]
    # Rack's path is raw bytes from the client, and JSON.generate raises on invalid UTF-8.
    path = String.new("#{env["SCRIPT_NAME"]}#{env["PATH_INFO"]}", encoding: Encoding::UTF_8).scrub
    started = @clock_ms.call
    response = @app.call(env)
    @logger.info(
      JSON.generate(
        {
          time:,
          method:,
          path:,
          status: response.first,
          duration_ms: (@clock_ms.call - started).round(2),
          request_id: env["skyward.request_id"]
        }
      )
    )
    response
  end
end
