# frozen_string_literal: true

require "json"

class Skyward::API::CLI::Serve::Reloader
  INTERVAL = 0.5 #: Float

  # @rbs @watch: ^() -> Hash[String, Time]
  # @rbs @load: ^() -> Skyward::API::_RackApp
  # @rbs @generate: ^() -> String?
  # @rbs @clock: ^() -> Float
  # @rbs @mutex: Thread::Mutex
  # @rbs @checked_at: Float
  # @rbs @files: Hash[String, Time]
  # @rbs @sources: Hash[String, Time]
  # @rbs @failure: String?
  # @rbs @app: Skyward::API::_RackApp

  # @rbs watch: ^() -> Hash[String, Time]
  # @rbs load: ^() -> Skyward::API::_RackApp
  # @rbs generate: ^() -> String?
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(watch:, load:, generate:, clock:)
    @watch = watch
    @load = load
    @generate = generate
    @clock = clock
    @mutex = Thread::Mutex.new
    @checked_at = clock.call
    @sources = {}
    @failure = nil
    @files = watch.call
    @app = attempt
  end

  # The app is taken under the lock but called outside it, so a request in
  # flight finishes on the app it started with.
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env) = @mutex.synchronize { current }.call(env)

  # Leaves the reload to the next request, which still sees the change.
  # @rbs return: void
  def regenerate
    @mutex.synchronize { generate(@watch.call) }
  # Runs on a thread of its own, which an exception would end. A file removed
  # between listing and reading it raises, and a generate that raised is run
  # again by the next reload, which answers with its error.
  rescue StandardError
    nil
  end

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
    failure = generate(@files)
    return failed(Skyward::Core::BootError.new(failure)) if failure

    @load.call
  # A SyntaxError or LoadError is a ScriptError, not a StandardError.
  rescue StandardError, ScriptError => e
    failed(e)
  end

  # Runs rbs-inline once for the .rb files as they are, whether regenerate or
  # a reload sees them first.
  # @rbs files: Hash[String, Time]
  # @rbs return: String?
  def generate(files)
    sources = files.select { |file, _time| file.end_with?(".rb") }
    return @failure if sources == @sources

    @failure = @generate.call
    @sources = sources
    @failure
  end

  # @rbs error: Exception
  # @rbs return: Skyward::API::_RackApp
  def failed(error)
    ->(env) { failure(error, env) } #: ^(Hash[String, untyped]) -> Skyward::API::rack_response
  end

  # The development 500 that Skyward::API::Middleware::Rescue answers, without a request
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
      # rbs-inline's failure is never raised, so has no backtrace.
      backtrace: error.backtrace || []
    }
    body = env["REQUEST_METHOD"] == "HEAD" ? [] : [JSON.generate(problem)] #: Array[String]
    [500, { "content-type" => "application/problem+json" }, body]
  end
end
