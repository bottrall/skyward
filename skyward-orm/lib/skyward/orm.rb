# frozen_string_literal: true

require "date"
require "skyward/core"
require "zeitwerk"
require_relative "orm/version"

loader = Zeitwerk::Loader.for_gem_extension(Skyward)
loader.inflector.inflect("orm" => "ORM", "sql" => "SQL", "sqlite" => "SQLite", "cli" => "CLI")
# The skyward executable loads it, and it defines no constant.
loader.ignore("#{__dir__}/orm/commands.rb")
loader.setup

# An app's signatures subclass Skyward::ORM::Record, so RBS needs its declaration.
dir = __dir__ #: String
Skyward::Core::Signatures.register(File.expand_path("../../sig", dir))

module Skyward
  # @rbs url: String
  # @rbs signatures: String
  # @rbs pool: Integer
  # @rbs check: bool
  # @rbs return: ORM::Connection::Database
  def self.connect(url, signatures: "sig", pool: 5, check: ORM::Connection::SESSION.check?)
    column_types = ORM::Tables::ColumnTypes.new(Core::Types::Reader.new(Core::Signatures.load(signatures)))
    adapter, location = ORM::Adapters.resolve(
      url,
      schemes: ORM::Adapters::SCHEMES,
      requirer: ->(feature) { require(feature) }
    )
    connections = ORM::Connection::Pool.new(adapter.pool_size(location, pool), -> { adapter.connect(location) })
    tables = connections.with { |connection| adapter.tables(connection) }
    database = ORM::Connection::Database.new(adapter, connections, column_types, tables, check:)
    database.check(ORM::Tables::Loaded.table_classes(ORM::Record)) if check
    ORM::Connection::SESSION.connect(database)
  end

  # @rbs [T] () { () -> T } -> T
  def self.transaction(&) = ORM::Connection::SESSION.database.transaction(&)

  # @rbs return: bool
  def self.transaction? = ORM::Connection::SESSION.database.transaction?

  # @rbs [T] (ORM::_Row[T] row, String sql, *untyped values) -> Array[T]
  #    | (String sql, *untyped values) -> Array[Hash[Symbol, untyped]]
  # Steep checks the body against both overloads at once, as one whose second
  # parameter is optional, which neither overload's is.
  def self.query(row, *arguments) # steep:ignore DifferentMethodParameterKind
    database = ORM::Connection::SESSION.database
    case row
    when String then database.hashes(row, arguments)
    when Class then database.rows(row, arguments.fetch(0), arguments.drop(1))
    else raise ArgumentError, "Skyward.query takes a row class or the SQL as its first argument"
    end
  end

  # @rbs directory: String
  # @rbs return: Array[String]
  def self.migrate(directory)
    migrated = ORM::Connection::SESSION.database.migrate(ORM::Migrations::Runner.read(directory))
    case migrated
    when Array then migrated
    else raise ORM::MigrationError, ORM::Migrations::Runner.message(migrated)
    end
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
