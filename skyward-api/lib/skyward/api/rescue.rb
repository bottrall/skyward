# frozen_string_literal: true

require "json"

class Skyward::API::Rescue
  # @rbs @app: Skyward::API::_RackApp
  # @rbs @logger: Skyward::API::_Logger?
  # @rbs @on_error: Skyward::API::_OnError?
  # @rbs @development: bool

  # @rbs (Skyward::API::_RackApp app, logger: Skyward::API::_Logger?, on_error: Skyward::API::_OnError?,
  #       development: bool) -> void
  def initialize(app, logger:, on_error:, development:)
    @app = app
    @logger = logger
    @on_error = on_error
    @development = development
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env)
    # Read before the app runs, because middleware can rewrite the env in place.
    verb = env["REQUEST_METHOD"]
    @app.call(env)
  rescue StandardError => e
    request_id = env["skyward.request_id"]
    log(e, request_id)
    report(e, env, request_id)
    body = verb == "HEAD" ? [] : [JSON.generate(problem(e, request_id))] #: Array[String]
    [500, { "content-type" => "application/problem+json" }, body]
  end

  private

  # @rbs exception: StandardError
  # @rbs request_id: String?
  # @rbs return: void
  def log(exception, request_id)
    @logger&.info(
      JSON.generate(
        {
          level: "error",
          request_id:,
          class: exception.class.name,
          message: message(exception),
          backtrace: exception.backtrace
        }
      )
    )
  end

  # @rbs exception: StandardError
  # @rbs env: Hash[String, untyped]
  # @rbs request_id: String?
  # @rbs return: void
  def report(exception, env, request_id)
    @on_error&.call(exception, env)
  rescue StandardError => e
    log(e, request_id)
  end

  # @rbs exception: StandardError
  # @rbs request_id: String?
  # @rbs return: Hash[Symbol, untyped]
  def problem(exception, request_id)
    problem = { type: "about:blank", title: "Internal Server Error", status: 500, request_id: }
    # An exception's message can carry data, so only development shows it.
    return problem unless @development

    { **problem, detail: "#{exception.class}: #{message(exception)}", backtrace: exception.backtrace }
  end

  # @rbs exception: StandardError
  # @rbs return: String
  def message(exception)
    # A message can interpolate client path bytes, and JSON.generate raises on invalid UTF-8.
    String.new(exception.message, encoding: Encoding::UTF_8).scrub
  end
end
