# frozen_string_literal: true

require "skyward/core"
require "zeitwerk"
require_relative "api/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("api" => "API")
loader.setup

class Skyward::API
  extend Declarations
end
