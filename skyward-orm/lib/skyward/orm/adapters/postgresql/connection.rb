# frozen_string_literal: true

# PG::Connection runs SQL with exec_params, which returns a PG::Result, so this
# gives it the execute every adapter's connection has.
class Skyward::ORM::Adapters::PostgreSQL::Connection
  # What PostgreSQL reports when a migration changed a column a kept statement
  # returns. Other errors share its SQLSTATE, 0A000.
  REVALIDATE = 'RevalidateCachedQuery' #: String

  # @rbs @connection: PG::Connection
  # @rbs @statements: Skyward::ORM::Adapters::StatementCache[String]
  # @rbs @prepared: Integer
  # @rbs @changes: Integer

  # @rbs connection: PG::Connection
  # @rbs statements: Skyward::ORM::Adapters::StatementCache[String]
  # @rbs return: void
  def initialize(connection, statements)
    @connection = connection
    @statements = statements
    @prepared = 0
    @changes = 0
  end

  # The block form clears each result as soon as its rows are read, so the
  # rows it changed are kept for changes, as SQLite keeps them for its own.
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs prepare: bool
  # @rbs return: Array[Array[String?]]
  def execute(sql, binds = [], prepare: false)
    run(sql, binds, prepare) do |result|
      @changes = result.cmd_tuples
      result.values
    end
  end

  # @dynamic changes
  attr_reader :changes #: Integer

  # @rbs sql: String
  # @rbs *binds: untyped
  # @rbs prepare: bool
  # @rbs return: Array[Array[String?]]
  def execute2(sql, *binds, prepare: false) = run(sql, binds, prepare) { |result| [result.fields, *result.values] }

  # exec, unlike exec_params, runs every statement in the SQL.
  # @rbs sql: String
  # @rbs return: void
  def execute_batch(sql)
    @connection.exec(sql).clear
  end

  # Anything but idle counts, so a connection left mid-command or broken isn't
  # reused either.
  # @rbs return: bool
  def transaction_active? = @connection.transaction_status != PG::PQTRANS_IDLE

  # @rbs return: void
  def close
    @connection.close
  end

  private

  # @rbs [T] (String sql, Array[untyped] binds, bool prepare) { (PG::Result result) -> T } -> T
  def run(sql, binds, prepare, &)
    return @connection.exec_params(sql, binds, &) unless prepare && @statements.keeps?(binds)

    name = @statements.fetch(sql) || keep(sql)
    begin
      @connection.exec_prepared(name, binds, &)
    rescue PG::InvalidSqlStatementName, PG::FeatureNotSupported => e
      raise unless stale?(e)

      @statements.clear
      # The failed run aborted the transaction it was in, which refuses to
      # deallocate, so the statements stay on the server, unkept, until it
      # closes. Only outside one can it run again, and it never executed, so a
      # write isn't repeated.
      raise if transaction_active?

      @connection.exec('DEALLOCATE ALL').clear
      @connection.exec_prepared(keep(sql), binds, &)
    end
  end

  # Prepared before the evicted one is closed, so in an aborted transaction,
  # which refuses to prepare, nothing is evicted. It's closed with the
  # protocol's Close, which PgBouncer tracks as it does a prepare, and which,
  # unlike DEALLOCATE, succeeds on a name DISCARD ALL dropped, so it can't
  # abort a transaction. A name is never used again, so a statement an
  # exception left on the server unkept can't collide.
  # @rbs sql: String
  # @rbs return: String
  def keep(sql)
    name = "skyward_#{@prepared += 1}"
    @connection.prepare(name, sql).clear
    evicted = @statements.store(sql, name)
    @connection.close_prepared(evicted).clear if evicted
    name
  end

  # A statement DISCARD ALL dropped is missing, and one a migration changed the
  # result of is refused.
  # @rbs error: PG::Error
  # @rbs return: bool
  def stale?(error)
    error.is_a?(PG::InvalidSqlStatementName) ||
      error.result&.error_field(PG::PG_DIAG_SOURCE_FUNCTION) == REVALIDATE
  end
end
