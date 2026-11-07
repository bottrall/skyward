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

class Skyward::API
  # @rbs! type rack_response = [Integer, Hash[String, untyped], untyped]

  extend Declarations
end

module Skyward
  # @rbs &: (API::Builder) -> void
  # @rbs return: API::RequestId
  def self.app(&)
    raise ArgumentError, "Skyward.app needs a block that mounts the app's APIs" unless block_given?

    builder = API::Builder.new
    yield builder
    builder.freeze
    app = API::App.new(API::Router.new(builder.mounts), builder.middleware)
    API::RequestId.new(app, generate: -> { SecureRandom.uuid })
  end
end
