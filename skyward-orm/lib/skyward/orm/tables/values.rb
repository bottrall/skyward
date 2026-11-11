# frozen_string_literal: true

module Skyward::ORM::Tables::Values
  extend self

  ACCEPTED = {
    integer: [Integer],
    float: [Float, Integer],
    string: [String],
    bool: [TrueClass, FalseClass],
    date: [Date],
    time: [Time]
  }.freeze #: Hash[Symbol, Array[Module]]

  WRITTEN = {
    integer: "Integer",
    float: "Float",
    string: "String",
    bool: "bool",
    date: "Date",
    time: "Time"
  }.freeze #: Hash[Symbol, String]

  UNTYPED = "untyped, which takes any value but a Hash or a nested Array" #: String

  UNTYPED_WRITE = "untyped, which takes any one value but an Array, a Hash or a Range" #: String

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: String?
  def mismatch(table, column, value)
    refused = candidates(value).reject { |candidate| accepts?(column, candidate) }
    return if refused.empty?

    refusal(table, column, refused.first, UNTYPED)
  end

  # A write binds each value to one placeholder, so an Array or a Range, which
  # a where unpacks, is never one value, and the driver can't bind a Range.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: String?
  def write_mismatch(table, column, value)
    return if accepts?(column, value) && !value.is_a?(Range)

    refusal(table, column, value, UNTYPED_WRITE)
  end

  private

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs untyped: String
  # @rbs return: String
  def refusal(table, column, value, untyped)
    "#{table}.#{column.name} is #{written(column, untyped)}, not #{value.inspect} (#{value.class})"
  end

  # A range's nil end leaves it open, so it isn't a NULL to check.
  # @rbs value: untyped
  # @rbs return: Array[untyped]
  def candidates(value)
    case value
    when Array then value
    when Range then [value.begin, value.end].compact
    else [value]
    end
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: bool
  def accepts?(column, value)
    # The driver spreads an Array or a Hash across several placeholders, so
    # neither can be bound as one value, whatever the column's type.
    if column.type == :untyped then !value.is_a?(Array) && !value.is_a?(Hash)
    elsif value.nil? then column.nullable
    elsif column.type == :enum then column.symbols.include?(value)
    # A DateTime is a Date, but it encodes with its time, so it never equals a
    # stored date.
    elsif value.is_a?(DateTime) then false
    # SQLite stores NaN as NULL.
    else ACCEPTED.fetch(column.type).any? { |klass| value.is_a?(klass) } && !(value.is_a?(Float) && value.nan?)
    end
  end

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs untyped: String
  # @rbs return: String
  def written(column, untyped)
    case column.type
    when :untyped then untyped
    when :enum
      symbols = column.symbols.map(&:inspect).join(" | ")
      column.nullable ? "(#{symbols})?" : symbols
    else "#{WRITTEN.fetch(column.type)}#{"?" if column.nullable}"
    end
  end
end
