# frozen_string_literal: true

require "date"
require "skyward/core"
require "zeitwerk"
require_relative "orm/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("orm" => "ORM", "sql" => "SQL", "sqlite" => "SQLite")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/orm/commands.rb")
loader.setup

# An app's signatures subclass Skyward::ORM::Record, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Core::Signatures.register(File.expand_path("../../sig", dir))

module Skyward
  # @rbs url: String
  # @rbs signatures: String
  # @rbs return: ORM::Connection::Database
  def self.connect(url, signatures: "sig")
    column_types = ORM::Tables::ColumnTypes.new(Core::Types::Reader.new(Core::Signatures.load(signatures)))
    adapter, connection = ORM::Adapters.connect(
      url,
      schemes: ORM::Adapters::SCHEMES,
      requirer: ->(feature) { require(feature) }
    )
    ORM::Connection::SESSION.connect(
      ORM::Connection::Database.new(
        adapter,
        connection,
        column_types,
        adapter.tables(connection)
      )
    )
  end

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
