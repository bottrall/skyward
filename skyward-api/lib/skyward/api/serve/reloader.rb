# frozen_string_literal: true

require "json"

class Skyward::API::Serve::Reloader
  INTERVAL = 0.5 #: Float

  # @rbs @watch: ^() -> Hash[String, Time]
  # @rbs @load: ^() -> Skyward::API::_RackApp
  # @rbs @clock: ^() -> Float
  # @rbs @mutex: Thread::Mutex
  # @rbs @checked_at: Float
  # @rbs @files: Hash[String, Time]
  # @rbs @app: Skyward::API::_RackApp

  # @rbs watch: ^() -> Hash[String, Time]
  # @rbs load: ^() -> Skyward::API::_RackApp
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(watch:, load:, clock:)
    @watch = watch
    @load = load
    @clock = clock
    @mutex = Thread::Mutex.new
    @checked_at = clock.call
    @files = watch.call
    @app = attempt
  end

  # The app is taken under the lock but called outside it, so a request in
  # flight finishes on the app it started with.
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env) = @mutex.synchronize { current }.call(env)

  private

  # @rbs return: Skyward::API::_RackApp
  def current
    now = @clock.call
    return @app if now - @checked_at < INTERVAL

    @checked_at = now
    files = @watch.call
    return @app if files == @files

    @files = files
    @app = attempt
  end

  # @rbs return: Skyward::API::_RackApp
  def attempt
    @load.call
  # A SyntaxError or LoadError is a ScriptError, not a StandardError.
  rescue StandardError, ScriptError => e
    ->(env) { failure(e, env) } #: ^(Hash[String, untyped]) -> Skyward::API::rack_response
  end

  # The development 500 that Skyward::API::Rescue answers, without a request
  # ID: the app that assigns them is the one that failed to load.
  # @rbs error: Exception
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def failure(error, env)
    # A message can quote a source line's bytes, and JSON.generate raises on invalid UTF-8.
    message = String.new(error.message, encoding: Encoding::UTF_8).scrub
    problem = {
      type: "about:blank",
      title: "Internal Server Error",
      status: 500,
      detail: "#{error.class}: #{message}",
      backtrace: error.backtrace
    }
    body = env["REQUEST_METHOD"] == "HEAD" ? [] : [JSON.generate(problem)] #: Array[String]
    [500, { "content-type" => "application/problem+json" }, body]
  end
end
