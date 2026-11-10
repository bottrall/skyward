# frozen_string_literal: true

# PG::Connection runs SQL with exec_params, which returns a PG::Result, so this
# gives it the execute every adapter's connection has.
class Skyward::ORM::Adapters::PostgreSQL::Connection
  # @rbs @connection: PG::Connection
  # @rbs @changes: Integer

  # @rbs connection: PG::Connection
  # @rbs return: void
  def initialize(connection)
    @connection = connection
    @changes = 0
  end

  # The block form clears each result as soon as its rows are read, so the
  # rows it changed are kept for changes, as SQLite keeps them for its own.
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Array[Array[String?]]
  def execute(sql, binds = [])
    @connection.exec_params(sql, binds) do |result|
      @changes = result.cmd_tuples
      result.values
    end
  end

  # @dynamic changes
  attr_reader :changes #: Integer

  # @rbs sql: String
  # @rbs *binds: untyped
  # @rbs return: Array[Array[String?]]
  def execute2(sql, *binds) = @connection.exec_params(sql, binds) { |result| [result.fields, *result.values] }

  # exec, unlike exec_params, runs every statement in the SQL.
  # @rbs sql: String
  # @rbs return: void
  def execute_batch(sql)
    @connection.exec(sql).clear
  end
end
