# frozen_string_literal: true

require "skyward/core"
require "zeitwerk"
require_relative "api/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("api" => "API")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/api/commands.rb")
loader.setup
