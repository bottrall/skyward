# frozen_string_literal: true

# PG::Connection runs SQL with exec_params, which returns a PG::Result, so this
# gives it the execute every adapter's connection has.
class Skyward::ORM::Adapters::PostgreSQL::Connection
  # @rbs @connection: PG::Connection

  # @rbs connection: PG::Connection
  # @rbs return: void
  def initialize(connection)
    @connection = connection
  end

  # The block form clears each result as soon as its rows are read.
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Array[Array[String?]]
  def execute(sql, binds = []) = @connection.exec_params(sql, binds, &:values)

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
