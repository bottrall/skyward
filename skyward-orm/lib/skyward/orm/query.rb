# frozen_string_literal: true

# @rbs generic R
class Skyward::ORM::Query
  include Skyward::ORM::Queries::Clauses #[R]

  # @rbs **values: untyped
  # @rbs return: Integer | Skyward::ORM::Violation
  def update(**values)
    sql, binds = updating(values, nil)
    @session.database.write(@table, sql, binds)
  end

  # @rbs **values: untyped
  # @rbs return: Integer
  def update!(**values) = unviolated(update(**values))

  # @rbs return: Integer | Skyward::ORM::Violation
  def delete
    sql, binds = deleting(nil)
    @session.database.write(@table, sql, binds)
  end

  # @rbs return: Integer
  def delete! = unviolated(delete)
end
