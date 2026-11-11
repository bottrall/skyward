# frozen_string_literal: true

module Skyward::ORM::Tables::Values
  extend self

  ACCEPTED = {
    integer: [Integer],
    float: [Float, Integer],
    string: [String],
    bool: [TrueClass, FalseClass],
    date: [Date],
    time: [Time],
    uuid: [String],
    int32: [Integer],
    int16: [Integer]
  }.freeze #: Hash[Symbol, Array[Module]]

  WRITTEN = {
    integer: "Integer",
    float: "Float",
    string: "String",
    bool: "bool",
    date: "Date",
    time: "Time",
    uuid: "uuid",
    int32: "int32",
    int16: "int16",
    json: "Hash[String, untyped]"
  }.freeze #: Hash[Symbol, String]

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/ #: Regexp

  RANGES = {
    int32: -(2**31)...(2**31),
    int16: -(2**15)...(2**15)
  }.freeze #: Hash[Symbol, Range[Integer]]

  UNTYPED = "untyped, which takes any value but a Hash or a nested Array" #: String

  UNTYPED_WRITE = "untyped, which takes any one value but an Array, a Hash or a Range" #: String

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: String?
  def mismatch(table, column, value)
    # PostgreSQL compares jsonb by value, but SQLite compares the JSON's text,
    # so the two would match different rows for anything but NULL.
    if column.type == :json && !value.nil?
      return "#{table}.#{column.name} is a #{WRITTEN.fetch(:json)} column, which where matches only to nil. " \
             "Match its contents with an SQL string."
    end

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
    return json_mismatch(table, column, value) if column.type == :json && !value.nil?
    return if accepts?(column, value) && !value.is_a?(Range)

    refusal(table, column, value, UNTYPED_WRITE)
  end

  private

  # A row reads back == to the one written only when its JSON holds each value
  # as it is: a Symbol or a Time would come back a String.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs value: untyped
  # @rbs return: String?
  def json_mismatch(table, column, value)
    return refusal(table, column, value, UNTYPED_WRITE) unless value.is_a?(Hash)

    found = stray(value, column.name.name)
    return unless found

    refused, at = found
    "#{refusal(table, column, refused, UNTYPED_WRITE)} #{at}"
  end

  # The first value JSON doesn't hold as it is, and where it is.
  # @rbs value: untyped
  # @rbs path: String
  # @rbs return: [untyped, String]?
  def stray(value, path)
    case value
    when nil, true, false, Integer, String then nil
    when Float then [value, "at #{path}"] unless value.finite?
    when Array then value.each_with_index.lazy.filter_map { |item, index| stray(item, "#{path}[#{index}]") }.first
    when Hash
      value.lazy.filter_map do |key, item|
        if key.is_a?(String) then stray(item, "#{path}[#{key.inspect}]")
        else [key, "as a key of #{path}"] #: [untyped, String]
        end
      end.first
    else [value, "at #{path}"]
    end
  end

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
    else ACCEPTED.fetch(column.type).any? { |klass| value.is_a?(klass) } && holds?(column.type, value)
    end
  end

  # A value of the right class that the column can't store would only fail in
  # the database, with an error that doesn't name the column.
  # @rbs type: Skyward::ORM::Tables::column_type
  # @rbs value: untyped
  # @rbs return: bool
  def holds?(type, value)
    case type
    # SQLite stores NaN as NULL.
    when :float then !(value.is_a?(Float) && value.nan?)
    when :uuid then UUID.match?(value)
    when :int32, :int16 then RANGES.fetch(type).cover?(value)
    else true
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
