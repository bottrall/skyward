# frozen_string_literal: true

# SQLite3::Database#execute prepares, runs and closes a new statement on every
# call, so this keeps the statements it's asked to prepare, to run again.
class Skyward::ORM::Adapters::SQLite::Connection
  # @rbs @database: SQLite3::Database[SQLite3::result_as_array]
  # @rbs @statements: Skyward::ORM::Adapters::StatementCache[SQLite3::Statement]

  # @rbs database: SQLite3::Database[SQLite3::result_as_array]
  # @rbs statements: Skyward::ORM::Adapters::StatementCache[SQLite3::Statement]
  # @rbs return: void
  def initialize(database, statements)
    @database = database
    @statements = statements
  end

  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs prepare: bool
  # @rbs return: Array[Array[untyped]]
  def execute(sql, binds = [], prepare: false)
    statement = kept(sql, binds, prepare)
    return @database.execute(sql, binds) unless statement

    run(statement, binds)
  end

  # @rbs sql: String
  # @rbs *binds: untyped
  # @rbs prepare: bool
  # @rbs return: Array[Array[untyped]]
  def execute2(sql, *binds, prepare: false)
    statement = kept(sql, binds, prepare)
    return @database.execute2(sql, *binds) unless statement

    rows = run(statement, binds)
    # Read after the run, rather than through Statement#columns, which caches
    # them: SQLite prepares a statement again once the schema changes, so a
    # SELECT * returns a column a migration added.
    [Array.new(statement.column_count) { |index| statement.column_name(index) }, *rows]
  end

  # @rbs sql: String
  # @rbs return: void
  def execute_batch(sql)
    @database.execute_batch(sql)
  end

  # @rbs return: Integer
  def changes = @database.changes

  # @rbs return: bool
  def transaction_active? = @database.transaction_active?

  # SQLite holds a closed database open until each of its statements is closed too.
  # @rbs return: void
  def close
    @statements.clear.each(&:close)
    @database.close
  end

  private

  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs prepare: bool
  # @rbs return: SQLite3::Statement?
  def kept(sql, binds, prepare)
    return unless prepare && @statements.keeps?(binds)

    @statements.fetch(sql) || @database.prepare(sql).tap do |statement|
      @statements.store(sql, statement)&.close
    end
  end

  # Reset however it ends, so no kept statement is left running, where it would
  # stop a migration's DROP TABLE with "database table is locked".
  # @rbs statement: SQLite3::Statement
  # @rbs binds: Array[untyped]
  # @rbs return: Array[Array[untyped]]
  def run(statement, binds)
    statement.bind_params(binds)
    statement.to_a
  ensure
    statement.reset!
  end
end
