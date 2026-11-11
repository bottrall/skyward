# frozen_string_literal: true

# @rbs generic R
class Skyward::ORM::Projection
  include Skyward::ORM::Queries::Clauses #[R]

  # @rbs **values: untyped
  # @rbs return: R | Skyward::ORM::Violation
  def insert(**values)
    require_insertable
    database = @session.database
    sql, binds = Skyward::ORM::Statements.insert(database.adapter, database.column_types, @table, values)
    written = returning(sql, binds)
    case written
    when Skyward::ORM::Violation then written
    else written.fetch(0)
    end
  end

  # @rbs **values: untyped
  # @rbs return: R
  def insert!(**values) = unviolated(insert(**values))

  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: Array[R] | Skyward::ORM::Violation
  def insert_all(rows)
    require_insertable
    return [] if rows.empty?

    database = @session.database
    sql, binds = Skyward::ORM::Statements.insert_all(database.adapter, database.column_types, @table, rows)
    returning(sql, binds)
  end

  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: Array[R]
  def insert_all!(rows) = unviolated(insert_all(rows))

  # @rbs **values: untyped
  # @rbs return: Array[R] | Skyward::ORM::Violation
  def update(**values)
    sql, binds = updating(values)
    returning(sql, binds)
  end

  # @rbs **values: untyped
  # @rbs return: Array[R]
  def update!(**values) = unviolated(update(**values))

  # @rbs return: Array[R] | Skyward::ORM::Violation
  def delete
    sql, binds = deleting
    returning(sql, binds)
  end

  # @rbs return: Array[R]
  def delete! = unviolated(delete)

  private

  # An INSERT takes none of a query's clauses, so the query can only say what
  # comes back.
  # @rbs return: void
  def require_insertable
    refused = [("conditions" if @scope == :narrowed), *clauses].compact
    return if refused.empty?

    raise ArgumentError,
          "#{@table} can't insert through a query with #{listing(refused)}. " \
          "Start from #{@table}.into, with nothing else on it."
  end

  # Steep can't tie the row class to R, so the rows are untyped here and each
  # public method types them.
  # @rbs sql: String
  # @rbs binds: Array[untyped]
  # @rbs return: Array[untyped] | Skyward::ORM::Violation
  def returning(sql, binds)
    returned = Skyward::ORM::Statements.returning(Skyward::ORM::Tables::Members.of(@row))
    @session.database.write_returning(@table, @row, "#{sql} #{returned}", binds)
  end
end
