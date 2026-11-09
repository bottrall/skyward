# frozen_string_literal: true

class Skyward::ORM::Record
  extend Skyward::ORM::Tables::Declarations

  # Each table class defines these for its columns, from Skyward::ORM::Tables::Rows.source.
  # @rbs!
  #   private def initialize_columns: (Hash[Symbol, untyped] columns) -> void
  #   def to_h: () -> Hash[Symbol, untyped]
  #   def ==: (untyped other) -> bool
  #   def eql?: (untyped other) -> bool
  #   def hash: () -> Integer

  # @dynamic initialize_columns, to_h, ==, eql?, hash
  class_eval(Skyward::ORM::Tables::Rows.source([]), __FILE__, __LINE__)

  # @rbs return: Skyward::ORM::Query[instance]
  def self.all = Skyward::ORM::Query.new(self, Skyward::ORM::Connection::SESSION, all: true)

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
  # @rbs **directions: Skyward::ORM::Query::direction
  # @rbs return: Skyward::ORM::Query[instance]
  def self.order(*columns, **directions) = all.order(*columns, **directions)

  # @rbs **conditions: untyped
  # @rbs return: instance?
  def self.find_by(**conditions) = all.find_by(**conditions)

  # @rbs **values: untyped
  # @rbs return: instance | Skyward::ORM::Violation
  def self.insert(**values)
    database = Skyward::ORM::Connection::SESSION.database
    sql, binds = Skyward::ORM::Statements.insert(database.adapter, database.column_types, self, values)
    written = database.write(self, self, sql, binds)
    case written
    when Skyward::ORM::Violation then written
    else written.fetch(0)
    end
  end

  # @rbs **values: untyped
  # @rbs return: instance
  def self.insert!(**values)
    row = insert(**values)
    case row
    when Skyward::ORM::Violation then raise Skyward::ORM::ViolationError, row
    else row
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

  # @rbs keys: Array[Symbol]?
  # @rbs return: Hash[Symbol, untyped]
  def deconstruct_keys(keys) = keys ? to_h.slice(*keys) : to_h

  # @rbs return: String
  def inspect = "#<#{self.class} #{to_h.map { |column, value| "#{column}=#{value.inspect}" }.join(", ")}>"
end
