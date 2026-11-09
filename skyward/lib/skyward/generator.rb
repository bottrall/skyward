# frozen_string_literal: true

require "skyward/core"
require "zeitwerk"
require_relative "version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("cli" => "CLI")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/generator/commands.rb")
# It defines Skyward::VERSION, not the Skyward::Version its name means to the loader.
loader.ignore("#{__dir__}/version.rb")
loader.setup

module Skyward::Generator
end
