# frozen_string_literal: true

require "securerandom"
require "skyward/core"
require "zeitwerk"
require_relative "api/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("api" => "API")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/api/commands.rb")
loader.setup

# An app's signatures subclass Skyward::API, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Signatures.register(File.expand_path("../../sig", dir))

class Skyward::API
  # @rbs! type rack_response = [Integer, Hash[String, untyped], untyped]

  extend Declarations
end

module Skyward
  # @rbs (?signatures: String, ?logger: API::_Logger?, ?on_error: API::_OnError?) { (API::Builder) -> void } -> API::RequestId
  def self.app(signatures: "sig", logger: API::LineLogger.new($stdout), on_error: nil, &)
    raise ArgumentError, "Skyward.app needs a block that mounts the app's APIs" unless block_given?

    builder = API::Builder.new
    yield builder
    builder.freeze
    reader = Types::Reader.new(Signatures.load(signatures))
    router = API::Router.new(API::Boot.endpoints(builder.mounts, reader:))
    app = API::Rescue.new(
      API::App.new(router, API::Static.new(builder.statics), builder.middleware),
      logger:,
      on_error:,
      development: ENV.fetch("RACK_ENV") { ENV.fetch("APP_ENV", nil) } == "development"
    )
    logged =
      if logger
        API::RequestLog.new(
          app,
          logger:,
          now: -> { Time.now },
          clock_ms: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) }
        )
      else
        app
      end
    API::RequestId.new(logged, generate: -> { SecureRandom.uuid })
  end
end
