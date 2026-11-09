# frozen_string_literal: true

require "skyward/core"
require "zeitwerk"
require_relative "orm/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("orm" => "ORM", "sql" => "SQL")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/orm/commands.rb")
loader.setup

# An app's signatures subclass Skyward::ORM::Record, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Core::Signatures.register(File.expand_path("../../sig", dir))

module Skyward
  # @rbs expression: String
  # @rbs return: ORM::Tables::SQL
  def self.sql(expression)
    # Steep knows expression is a String, but untyped code can pass anything.
    unless expression.is_a?(String) # steep:ignore UnreachableBranch
      raise ArgumentError, "Skyward.sql takes the SQL as a String, not #{expression.inspect}"
    end

    ORM::Tables::SQL.new(expression: expression.dup.freeze)
  end
end
