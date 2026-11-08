# frozen_string_literal: true

require "securerandom"
require "skyward/core"
require "zeitwerk"
require_relative "api/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("api" => "API", "openapi" => "OpenAPI")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/api/commands.rb")
loader.setup

# An app's signatures subclass Skyward::API, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Signatures.register(File.expand_path("../../sig", dir))

class Skyward::API
  # @rbs! type rack_response = [Integer, Hash[String, untyped], untyped]

  extend Declarations
  include Responses
end

module Skyward
  # @rbs! type rack = [Integer, Hash[String, String], untyped]

  # @rbs (?signatures: String, ?docs: bool, ?title: String, ?version: String, ?description: String?,
  #   ?schema_names: Hash[Class, String], ?scalar_url: String, ?logger: API::_Logger?, ?on_error: API::_OnError?,
  #   ?max_body_size: Integer) { (API::Builder) -> void } -> API::RequestId
  def self.app(
    signatures: "sig",
    docs: false,
    title: "API",
    version: "0.1.0",
    description: nil,
    schema_names: {},
    scalar_url: API::Docs::SCALAR_URL,
    logger: API::LineLogger.new($stdout),
    on_error: nil,
    max_body_size: 1_048_576,
    &
  )
    raise ArgumentError, "Skyward.app needs a block that mounts the app's APIs" unless block_given?

    builder = API::Builder.new
    yield builder
    builder.freeze
    reader = Types::Reader.new(Signatures.load(signatures))
    endpoints = API::Boot.endpoints(builder.mounts, reader:, max_body_size:)
    static = API::Static.new(builder.statics)
    documents =
      if docs
        openapi = API::OpenAPI.json(endpoints, static:, title:, version:, description:, schema_names:)
        page = API::Docs.page(title:, scalar_url:)
        {
          API::OpenAPI::PATH => API::App::Document.new(type: API::OpenAPI::JSON_TYPE, body: openapi),
          API::Docs::PATH => API::App::Document.new(type: API::Docs::HTML_TYPE, body: page)
        }
      else
        {} #: Hash[String, API::App::Document]
      end
    app = API::Rescue.new(
      API::App.new(API::Router.new(endpoints), static, builder.middleware, documents),
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

  # These response helpers are public here, for code outside an API class, such as a provider.
  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: BadRequest
  def self.bad_request(detail, headers: {}) = BadRequest.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Unauthorized
  def self.unauthorized(detail, headers: {}) = Unauthorized.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Forbidden
  def self.forbidden(detail, headers: {}) = Forbidden.new(detail:, headers:)

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: Redirect
  def self.redirect(to, status: 303, headers: {})
    unless Redirect::STATUSES.include?(status)
      raise ArgumentError, "A redirect's status must be one of #{Redirect::STATUSES.join(", ")}, not #{status}"
    end

    # A line break in the location would let it smuggle in headers of its own.
    raise ArgumentError, "A redirect's location can't contain a line break: #{to.inspect}" if to.match?(/[\r\n]/)

    Redirect.new(to:, status:, headers:)
  end
end
