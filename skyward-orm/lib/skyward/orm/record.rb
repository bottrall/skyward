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
