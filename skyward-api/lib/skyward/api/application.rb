# frozen_string_literal: true

class Skyward::API::Application
  # @rbs @app: Skyward::API::_RackApp
  # @rbs @openapi: ^() -> Skyward::API::OpenAPI::schema

  # @dynamic endpoints
  attr_reader :endpoints #: Array[Skyward::API::Router::Endpoint]

  # @rbs (Skyward::API::_RackApp app, endpoints: Array[Skyward::API::Router::Endpoint],
  #       openapi: ^() -> Skyward::API::OpenAPI::schema) -> void
  def initialize(app, endpoints:, openapi:)
    @app = app
    @endpoints = endpoints
    @openapi = openapi
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::rack_response
  def call(env) = @app.call(env)

  # Built when asked for, because only an app with docs: true refuses to boot over a document that can't be built.
  # @rbs return: Skyward::API::OpenAPI::schema
  def openapi = @openapi.call
end
