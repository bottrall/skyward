# frozen_string_literal: true

require "zeitwerk"
require_relative "core/version"

# Skyward Core owns the Skyward namespace: its version.rb opens it, and every
# Skyward gem's loader, this one included, extends it.
loader = Zeitwerk::Loader.for_gem_extension(Skyward)
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/core/commands.rb")
loader.setup

dir = __dir__ #: String
Skyward::Signatures.register(File.expand_path("../../sig", dir))
