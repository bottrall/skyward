# frozen_string_literal: true

# Only one fiber uses a connection at a time, so its cache takes no lock.
# @rbs generic S
class Skyward::ORM::Adapters::StatementCache
  LIMIT = 1_000 #: Integer

  # A statement with more binds isn't kept. Varying IN lists and multi-row
  # inserts are what reach it: each length is different SQL that would churn
  # the cache, PostgreSQL keeps a large plan for each, and parsing is a small
  # part of their cost.
  MAX_BINDS = 100 #: Integer

  # @rbs @limit: Integer
  # @rbs @statements: Hash[String, S]

  # @rbs limit: Integer
  # @rbs return: void
  def initialize(limit = LIMIT)
    @limit = limit
    @statements = {}
  end

  # @rbs binds: Array[untyped]
  # @rbs return: bool
  def keeps?(binds) = binds.size <= MAX_BINDS

  # @rbs sql: String
  # @rbs return: S?
  def fetch(sql)
    # A Hash keeps its keys in insertion order, so moving each hit to the end
    # keeps the least recently used first.
    statement = @statements.delete(sql)
    @statements[sql] = statement if statement
  end

  # @rbs sql: String
  # @rbs statement: S
  # @rbs return: S?
  def store(sql, statement)
    @statements[sql] = statement
    @statements.shift&.last if @statements.size > @limit
  end

  # @rbs return: Array[S]
  def clear
    cleared = @statements.values
    @statements = {}
    cleared
  end
end
