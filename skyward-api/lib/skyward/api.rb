# frozen_string_literal: true

require "securerandom"
require "skyward/core"
require "zeitwerk"
require_relative "api/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("api" => "API", "cli" => "CLI", "openapi" => "OpenAPI")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/api/commands.rb")
loader.setup

# An app's signatures subclass Skyward::API, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Core::Signatures.register(File.expand_path("../../sig", dir))

class Skyward::API
  # @rbs! type rack_response = [Integer, Hash[String, untyped], untyped]
  # @rbs! type rack = [Integer, Hash[String, String], untyped]

  extend Endpoints::Declarations
  include Endpoints::Helpers
end

module Skyward
  # @rbs (?signatures: String, ?strict: bool, ?docs: bool, ?title: String, ?version: String, ?description: String?,
  #   ?schema_names: Hash[Class, String], ?scalar_url: String, ?logger: API::_Logger?, ?on_error: API::_OnError?,
  #   ?max_body_size: Integer) { (API::Assembly::Builder) -> void } -> API::Assembly::Application
  def self.app(
    signatures: "sig",
    strict: false,
    docs: false,
    title: "API",
    version: "0.1.0",
    description: nil,
    schema_names: {},
    scalar_url: API::OpenAPI::Docs::SCALAR_URL,
    logger: API::Middleware::LineLogger.new($stdout),
    on_error: nil,
    max_body_size: 1_048_576,
    &
  )
    raise ArgumentError, "Skyward.app needs a block that mounts the app's APIs" unless block_given?

    builder = API::Assembly::Builder.new
    yield builder
    builder.freeze
    reader = Core::Types::Reader.new(Core::Signatures.load(signatures))
    endpoints = API::Assembly::Boot.endpoints(
      builder.mounts,
      providers: builder.providers,
      reader:,
      max_body_size:,
      strict: strict || ENV.fetch("SKYWARD_STRICT", nil) == "1"
    )
    static = API::Assembly::Static.new(builder.statics)
    openapi = -> { API::OpenAPI.document(endpoints, title:, version:, description:, schema_names:) }
    documents =
      if docs
        json = API::OpenAPI.json(endpoints, static:, document: openapi)
        page = API::OpenAPI::Docs.page(title:, scalar_url:)
        document = API::Assembly::Dispatcher::Document
        {
          API::OpenAPI::PATH => document.new(type: API::OpenAPI::JSON_TYPE, body: json),
          API::OpenAPI::Docs::PATH => document.new(type: API::OpenAPI::Docs::HTML_TYPE, body: page)
        }
      else
        {} #: Hash[String, API::Assembly::Dispatcher::Document]
      end
    app = API::Middleware::Rescue.new(
      API::Assembly::Dispatcher.new(API::Routing::Router.new(endpoints), static, builder.middleware, documents),
      logger:,
      on_error:,
      development: ENV.fetch("RACK_ENV") { ENV.fetch("APP_ENV", nil) } == "development"
    )
    logged =
      if logger
        API::Middleware::RequestLog.new(
          app,
          logger:,
          now: -> { Time.now },
          clock_ms: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) }
        )
      else
        app
      end
    API::Assembly::Application.new(
      API::Middleware::RequestId.new(logged, generate: -> { SecureRandom.uuid }),
      endpoints:,
      openapi:
    )
  end

  # These response helpers are public here, for code outside an API class, such as a provider.
  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: API::Responses::BadRequest
  def self.bad_request(detail, headers: {}) = API::Responses::BadRequest.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: API::Responses::Unauthorized
  def self.unauthorized(detail, headers: {}) = API::Responses::Unauthorized.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: API::Responses::Forbidden
  def self.forbidden(detail, headers: {}) = API::Responses::Forbidden.new(detail:, headers:)

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: API::Responses::Redirect
  def self.redirect(to, status: 303, headers: {})
    statuses = API::Responses::Redirect::STATUSES
    unless statuses.include?(status)
      raise ArgumentError, "A redirect's status must be one of #{statuses.join(", ")}, not #{status}"
    end

    # A line break in the location would let it smuggle in headers of its own.
    raise ArgumentError, "A redirect's location can't contain a line break: #{to.inspect}" if to.match?(/[\r\n]/)

    API::Responses::Redirect.new(to:, status:, headers:)
  end
end
