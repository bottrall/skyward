# frozen_string_literal: true

require "date"
require "json"

module Skyward::API::Coercer
  extend self

  # @rbs!
  #   type result = Ok | Invalid
  #   type t = ^(untyped raw, String at) -> result

  Error = Data.define(
    :at, #: String
    :message #: String
  )

  Ok = Data.define(
    :value #: untyped
  )

  Invalid = Data.define(
    :errors #: Array[Error]
  )

  # Coercion stops once it has found this many problems, so a small body can't
  # produce a large response.
  MAX_ERRORS = 1_000 #: Integer

  # INTEGER, DATE and TIME match a String's bytes, because a path parameter
  # can be any bytes, and Regexp#match raises on a String that isn't UTF-8.
  INTEGER = /\A-?\d+\z/ #: Regexp

  BOOLEANS = { "true" => true, "false" => false, "1" => true, "0" => false }.freeze #: Hash[String, bool]

  DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/ #: Regexp

  # The fraction is cut to nanoseconds, which bounds what converting it costs.
  TIME = /
    \A(\d{4}-\d{2}-\d{2})
    T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.(\d{1,9})\d*+)?
    (Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z
  /x #: Regexp

  NAMES = {
    integer: "Integer",
    float: "Float",
    string: "String",
    bool: "bool",
    date: "Date",
    time: "Time",
    untyped: "untyped"
  }.freeze #: Hash[Skyward::Types::scalar, String]

  FORMATS = { date: "Date (YYYY-MM-DD)", time: "Time (ISO 8601)" }.freeze #: Hash[Skyward::Types::scalar, String]

  # Path and query values are Strings, so with strings: true a coercer parses them.
  # @rbs type: Skyward::Types::t
  # @rbs strings: bool
  # @rbs limit: Integer
  # @rbs return: t
  def compile(type, strings:, limit: MAX_ERRORS)
    case type
    when Skyward::Types::Scalar then scalar(type, parser(type.name, strings))
    when Skyward::Types::Literal then literal(type, strings)
    when Skyward::Types::Enum then enum(type)
    when Skyward::Types::Nullable then nullable(compile(type.type, strings:, limit:))
    when Skyward::Types::ArrayOf then array(type, compile(type.type, strings:, limit:), strings, limit)
    when Skyward::Types::Record then object(type, strings, limit, &:itself)
    when Skyward::Types::Named
      klass = type.klass
      object(type, strings, limit) { |fields| klass.new(**fields) }
    # A union reports its own mismatch, so a member only needs to know whether it fits.
    else union(type, type.types.map { |member| compile(member, strings:, limit: 1) })
    end
  end

  # @rbs type: Skyward::Types::t
  # @rbs required: bool
  # @rbs at: String
  # @rbs return: result?
  def absent(type, required, at)
    return unless required
    return Ok.new(value: nil) if type.is_a?(Skyward::Types::Nullable)

    Invalid.new(errors: [Error.new(at:, message: "is required")])
  end

  # @rbs results: Hash[Symbol, result]
  # @rbs return: result
  def combine(results)
    errors = errors(results.values)
    return Invalid.new(errors:) unless errors.empty?

    ok = results #: Hash[Symbol, Ok]
    Ok.new(value: ok.transform_values(&:value))
  end

  private

  # @rbs type: Skyward::Types::t
  # @rbs parse: ^(untyped) -> Ok?
  # @rbs return: t
  def scalar(type, parse) = ->(raw, at) { parse.call(raw) || mismatch(type, raw, at) }

  # @rbs name: Skyward::Types::scalar
  # @rbs strings: bool
  # @rbs return: ^(untyped) -> Ok?
  def parser(name, strings)
    case name
    when :integer then ->(raw) { integer(raw, strings) }
    when :float then ->(raw) { float(raw, strings) }
    when :bool then ->(raw) { bool(raw, strings) }
    when :string then ->(raw) { Ok.new(value: raw) if raw.is_a?(String) }
    when :date then ->(raw) { date(raw) }
    when :time then ->(raw) { time(raw) }
    else ->(raw) { Ok.new(value: raw) if !strings || raw.is_a?(String) }
    end
  end

  # @rbs raw: untyped
  # @rbs strings: bool
  # @rbs return: Ok?
  def integer(raw, strings)
    case raw
    when Integer then Ok.new(value: raw)
    when String then Ok.new(value: raw.to_i) if strings && INTEGER.match?(raw.b)
    end
  end

  # @rbs raw: untyped
  # @rbs strings: bool
  # @rbs return: Ok?
  def float(raw, strings)
    number =
      case raw
      when Integer, Float then raw.to_f
      when String then Float(raw, exception: false) if strings
      end
    Ok.new(value: number) if number&.finite?
  end

  # @rbs raw: untyped
  # @rbs strings: bool
  # @rbs return: Ok?
  def bool(raw, strings)
    case raw
    when true, false then Ok.new(value: raw)
    when String then Ok.new(value: BOOLEANS.fetch(raw)) if strings && BOOLEANS.key?(raw)
    end
  end

  # @rbs raw: untyped
  # @rbs return: Ok?
  def date(raw)
    match = DATE.match(raw.b) if raw.is_a?(String)
    return unless match

    year, month, day = match.captures.map(&:to_i) #: [Integer, Integer, Integer]
    Ok.new(value: Date.new(year, month, day)) if Date.valid_date?(year, month, day)
  end

  # @rbs raw: untyped
  # @rbs return: Ok?
  def time(raw)
    match = TIME.match(raw.b) if raw.is_a?(String)
    # Time.new rolls an impossible day, like February 30, into the next month.
    day = date(match[1]) if match
    return unless match && day

    _, hour, minute, second, fraction, zone = match.captures
    on = day.value
    seconds = Rational("#{second}.#{fraction || 0}")
    Ok.new(value: Time.new(on.year, on.month, on.day, hour.to_i, minute.to_i, seconds, zone))
  end

  # @rbs type: Skyward::Types::Literal
  # @rbs strings: bool
  # @rbs return: t
  def literal(type, strings)
    value = type.value
    name =
      case value
      when Integer then :integer
      when String then :string
      when nil then :untyped
      else :bool
      end #: Skyward::Types::scalar
    parse = parser(name, strings)
    lambda do |raw, at|
      parsed = parse.call(raw)
      parsed && parsed.value == value ? parsed : mismatch(type, raw, at)
    end
  end

  # @rbs type: Skyward::Types::Enum
  # @rbs return: t
  def enum(type)
    symbols = type.symbols.to_h { |symbol| [symbol.name, symbol] }
    lambda do |raw, at|
      symbol = symbols.fetch(raw, nil)
      symbol ? Ok.new(value: symbol) : mismatch(type, raw, at)
    end
  end

  # @rbs coercer: t
  # @rbs return: t
  def nullable(coercer) = ->(raw, at) { raw.nil? ? Ok.new(value: nil) : coercer.call(raw, at) }

  # @rbs type: Skyward::Types::ArrayOf
  # @rbs item: t
  # @rbs strings: bool
  # @rbs limit: Integer
  # @rbs return: t
  def array(type, item, strings, limit)
    lambda do |raw, at|
      values =
        case raw
        when Array then raw
        # A query string repeats a key for each item, so one value is one item.
        when String then [raw] if strings
        end
      next mismatch(type, raw, at) unless values

      results = items(values, item, at, limit)
      errors = errors(results)
      next Invalid.new(errors:) unless errors.empty?

      ok = results #: Array[Ok]
      Ok.new(value: ok.map(&:value))
    end
  end

  # @rbs values: Array[untyped]
  # @rbs item: t
  # @rbs at: String
  # @rbs limit: Integer
  # @rbs return: Array[result]
  def items(values, item, at, limit)
    none = [[], 0] #: [Array[result], Integer]
    coerced = values.each_with_index.reduce(none) do |state, (value, index)|
      done, count = state
      break state if count >= limit

      result = item.call(value, "#{at}[#{index}]")
      # Appended in place: copying the array for each item would be quadratic.
      [done << result, count + errors([result]).size]
    end
    coerced.first
  end

  # @rbs type: Skyward::Types::Record | Skyward::Types::Named
  # @rbs strings: bool
  # @rbs limit: Integer
  # @rbs &: (Hash[Symbol, untyped]) -> untyped
  # @rbs return: t
  def object(type, strings, limit, &)
    fields = type.fields.map do |field|
      [field, compile(field.type, strings:, limit:)]
    end #: Array[[Skyward::Types::Field, t]]
    lambda do |raw, at|
      next mismatch(type, raw, at) unless raw.is_a?(Hash)

      none = [[], 0] #: [Array[[Symbol, result]], Integer]
      coerced = fields.reduce(none) do |state, (field, coercer)|
        done, count = state
        break state if count >= limit

        name = field.name.to_s
        found = "#{at}.#{name}"
        result = raw.key?(name) ? coercer.call(raw.fetch(name), found) : absent(field.type, field.required, found)
        case result
        when Ok then [done << [field.name, result], count]
        when Invalid then [done << [field.name, result], count + result.errors.size]
        else state
        end
      end
      combined = combine(coerced.first.to_h)
      combined.is_a?(Ok) ? Ok.new(value: yield(combined.value)) : combined
    end
  end

  # @rbs type: Skyward::Types::Union
  # @rbs coercers: Array[t]
  # @rbs return: t
  def union(type, coercers)
    lambda do |raw, at|
      coercers.lazy.map { |coercer| coercer.call(raw, at) }.find { |result| result.is_a?(Ok) } ||
        mismatch(type, raw, at)
    end
  end

  # @rbs results: Array[result]
  # @rbs return: Array[Error]
  def errors(results) = results.flat_map { |result| result.is_a?(Invalid) ? result.errors : [] }

  # @rbs type: Skyward::Types::t
  # @rbs raw: untyped
  # @rbs at: String
  # @rbs return: Invalid
  def mismatch(type, raw, at)
    expected = type.is_a?(Skyward::Types::Scalar) ? FORMATS.fetch(type.name) { written(type) } : written(type)
    # A path parameter can be any bytes, and a body any number, nested as deep
    # as JSON.parse allows, all of which JSON.generate refuses by default.
    got = JSON.generate(raw.is_a?(String) ? raw.scrub : raw, allow_nan: true, max_nesting: false)
    Invalid.new(errors: [Error.new(at:, message: "expected #{expected}, got #{got}")])
  end

  # @rbs type: Skyward::Types::t
  # @rbs return: String
  def written(type)
    case type
    when Skyward::Types::Scalar then NAMES.fetch(type.name)
    when Skyward::Types::Literal then type.value.inspect
    when Skyward::Types::Enum then type.symbols.map(&:inspect).join(" | ")
    when Skyward::Types::Nullable then nullable_written(type.type)
    when Skyward::Types::ArrayOf then "Array[#{written(type.type)}]"
    when Skyward::Types::Record
      fields = type.fields.map { |field| "#{"?" unless field.required}#{field.name}: #{written(field.type)}" }
      "{ #{fields.join(", ")} }"
    when Skyward::Types::Named then type.name
    else type.types.map { |member| written(member) }.join(" | ")
    end
  end

  # @rbs type: Skyward::Types::t
  # @rbs return: String
  def nullable_written(type)
    plural = type.is_a?(Skyward::Types::Union) || (type.is_a?(Skyward::Types::Enum) && type.symbols.size > 1)
    plural ? "(#{written(type)})?" : "#{written(type)}?"
  end
end
