# frozen_string_literal: true

class Skyward::ORM::Record
  extend Skyward::ORM::Tables::Declarations

  # Each table class defines these for its columns, from Skyward::ORM::Tables::Rows.source.
  # @rbs!
  #   private def initialize_columns: (Hash[Symbol, untyped] columns) -> void
  #   private def load_columns: (*untyped values) -> self
  #   def to_h: () -> Hash[Symbol, untyped]
  #   def deconstruct_keys: (Array[Symbol]? keys) -> Hash[Symbol, untyped]
  #   def inspect: () -> String
  #   def ==: (untyped other) -> bool
  #   def eql?: (untyped other) -> bool
  #   def hash: () -> Integer

  # @dynamic initialize_columns, load_columns, to_h, deconstruct_keys, inspect, ==, eql?, hash
  class_eval(Skyward::ORM::Tables::Rows.source([]), __FILE__, __LINE__)

  # @rbs return: Skyward::ORM::Query[instance]
  def self.all = Skyward::ORM::Query.new(self, Skyward::ORM::Connection::SESSION, scope: :all)

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: Skyward::ORM::Query[instance]
  def self.join(table, **on) = all.join(table, **on)

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: Skyward::ORM::Query[instance]
  def self.left_join(table, **on) = all.left_join(table, **on)

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[instance]
  def self.where(sql = nil, *values, **conditions) = all.where(sql, *values, **conditions)

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[instance]
  def self.exclude(sql = nil, *values, **conditions) = all.exclude(sql, *values, **conditions)

  # @rbs *columns: Symbol
  # @rbs **directions: Skyward::ORM::Queries::Clauses::direction
  # @rbs return: Skyward::ORM::Query[instance]
  def self.order(*columns, **directions) = all.order(*columns, **directions)

  # @rbs **conditions: untyped
  # @rbs return: instance?
  def self.find_by(**conditions) = all.find_by(**conditions)

  # @rbs [S] (Skyward::ORM::_Row[S] row, **String expressions) -> Skyward::ORM::Projection[S]
  def self.into(row, **expressions)
    Skyward::ORM::Query.new(self, Skyward::ORM::Connection::SESSION).into(row, **expressions)
  end

  # @rbs **values: untyped
  # @rbs return: Integer | Skyward::ORM::Violation
  def self.insert(**values)
    database = Skyward::ORM::Connection::SESSION.database
    sql, binds = Skyward::ORM::Statements.insert(database, self, values, nil)
    database.write(self, sql, binds)
  end

  # @rbs **values: untyped
  # @rbs return: Integer
  def self.insert!(**values)
    written = insert(**values)
    case written
    when Skyward::ORM::Violation then raise Skyward::ORM::ViolationError, written
    else written
    end
  end

  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: Integer | Skyward::ORM::Violation
  def self.insert_all(rows)
    return 0 if rows.empty?

    database = Skyward::ORM::Connection::SESSION.database
    sql, binds = Skyward::ORM::Statements.insert_all(
      database.adapter, database.column_types, database.tables, self, rows
    )
    database.write(self, sql, binds)
  end

  # @rbs rows: Array[Hash[Symbol, untyped]]
  # @rbs return: Integer
  def self.insert_all!(rows)
    written = insert_all(rows)
    case written
    when Skyward::ORM::Violation then raise Skyward::ORM::ViolationError, written
    else written
    end
  end

  # @rbs return: Array[Symbol]
  def self.members = schema.columns

  # Ruby warns whenever initialize is removed, so a table class redefines
  # initialize_columns instead, each time it gains a column.
  # @rbs **columns: untyped
  # @rbs return: void
  def initialize(**columns)
    initialize_columns(columns)
    freeze
  end

  # @rbs **changes: untyped
  # @rbs return: self
  def with(**changes) = self.class.new(**to_h, **changes) #: self
end
