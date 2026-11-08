# frozen_string_literal: true

require "date"
require "json"

module Skyward::API::Coercer
  extend self

  # @rbs!
  #   type result = Ok | Invalid
  #   type t = ^(untyped raw, String at) -> result
  #   type seen = Hash[[Integer, Integer], result]
  #   type coercer = ^(untyped raw, String at, seen seen) -> result

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

  # A message's expected type and a hash's key in a path are cut to this many
  # characters, so a large written type or key can't make a 422 many times
  # larger than the body that caused it.
  MAX_SHOWN = 200 #: Integer

  # Stands for every problem a union's member finds, since the union reports
  # none of them.
  MISFIT = Invalid.new(errors: [Error.new(at: "", message: "doesn't fit")]) #: Invalid

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
  # @rbs return: t
  def compile(type, strings:)
    coercer = build(type, strings, false, {})
    ->(raw, at) { coercer.call(raw, at, {}) }
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

  # A union reports its own mismatch, so with member: true a coercer stops at
  # its first problem and never writes a message.
  # @rbs type: Skyward::Types::t
  # @rbs strings: bool
  # @rbs member: bool
  # @rbs unions: Hash[[Skyward::Types::Union, bool], coercer]
  # @rbs return: coercer
  def build(type, strings, member, unions)
    expected = expectation(type) unless member
    limit = member ? 1 : MAX_ERRORS
    case type
    when Skyward::Types::Scalar then scalar(parser(type.name, strings), expected)
    when Skyward::Types::Literal then literal(type.value, strings, expected)
    when Skyward::Types::Enum then enum(type.symbols, expected)
    when Skyward::Types::Nullable then nullable(build(type.type, strings, member, unions))
    when Skyward::Types::ArrayOf then array(build(type.type, strings, member, unions), strings, limit, expected)
    when Skyward::Types::HashOf then hash_of(build(type.type, strings, member, unions), limit, expected)
    when Skyward::Types::Record then object(fields(type, strings, member, unions), limit, expected, &:itself)
    when Skyward::Types::Named
      klass = type.klass
      object(fields(type, strings, member, unions), limit, expected) { |values| klass.new(**values) }
    # Equal unions share one coercer, which is what lets one remember its results.
    else unions[[type, member]] ||= union(type.types.map { |one| build(one, strings, true, unions) }, member, expected)
    end
  end

  # @rbs type: Skyward::Types::Record | Skyward::Types::Named
  # @rbs strings: bool
  # @rbs member: bool
  # @rbs unions: Hash[[Skyward::Types::Union, bool], coercer]
  # @rbs return: Array[[Skyward::Types::Field, coercer]]
  def fields(type, strings, member, unions)
    type.fields.map { |field| [field, build(field.type, strings, member, unions)] }
  end

  # @rbs parse: ^(untyped) -> Ok?
  # @rbs expected: String?
  # @rbs return: coercer
  def scalar(parse, expected) = ->(raw, at, _seen) { parse.call(raw) || mismatch(expected, raw, at) }

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
    else ->(raw) { Ok.new(value: strings ? last(raw) : symbolized(raw)) }
    end
  end

  # A query key given more than once arrives as an Array of its values, of
  # which untyped takes the last, as Rack's params do.
  # @rbs raw: String | Array[String]
  # @rbs return: String?
  def last(raw) = raw.is_a?(Array) ? raw.last : raw

  # @rbs raw: untyped
  # @rbs return: untyped
  def symbolized(raw)
    case raw
    when Hash then raw.to_h { |key, value| [key.to_sym, symbolized(value)] }
    when Array then raw.map { |item| symbolized(item) }
    else raw
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

  # @rbs value: Skyward::Types::literal
  # @rbs strings: bool
  # @rbs expected: String?
  # @rbs return: coercer
  def literal(value, strings, expected)
    name =
      case value
      when Integer then :integer
      when String then :string
      when nil then :untyped
      else :bool
      end #: Skyward::Types::scalar
    parse = parser(name, strings)
    lambda do |raw, at, _seen|
      parsed = parse.call(raw)
      parsed && parsed.value == value ? parsed : mismatch(expected, raw, at)
    end
  end

  # @rbs symbols: Array[Symbol]
  # @rbs expected: String?
  # @rbs return: coercer
  def enum(symbols, expected)
    by_name = symbols.to_h { |symbol| [symbol.name, symbol] }
    lambda do |raw, at, _seen|
      symbol = by_name.fetch(raw, nil)
      symbol ? Ok.new(value: symbol) : mismatch(expected, raw, at)
    end
  end

  # @rbs coercer: coercer
  # @rbs return: coercer
  def nullable(coercer) = ->(raw, at, seen) { raw.nil? ? Ok.new(value: nil) : coercer.call(raw, at, seen) }

  # @rbs item: coercer
  # @rbs strings: bool
  # @rbs limit: Integer
  # @rbs expected: String?
  # @rbs return: coercer
  def array(item, strings, limit, expected)
    lambda do |raw, at, seen|
      values =
        case raw
        when Array then raw
        # A query string repeats a key for each item, so one value is one item.
        when String then [raw] if strings
        end
      next mismatch(expected, raw, at) unless values

      collected(items(values, item, limit, seen) { |index| "#{at}[#{index}]" }, &:itself)
    end
  end

  # @rbs value: coercer
  # @rbs limit: Integer
  # @rbs expected: String?
  # @rbs return: coercer
  def hash_of(value, limit, expected)
    lambda do |raw, at, seen|
      next mismatch(expected, raw, at) unless raw.is_a?(Hash)

      keys = raw.keys
      coerced = items(raw.values, value, limit, seen) do |index|
        # JSON-quoted so a dot or a bracket in a key can't be read as part of the path.
        "#{at}[#{JSON.generate(cut(keys.fetch(index)))}]"
      end
      collected(coerced) { |values| keys.zip(values).to_h }
    end
  end

  # @rbs values: Array[untyped]
  # @rbs item: coercer
  # @rbs limit: Integer
  # @rbs seen: seen
  # @rbs &: (Integer) -> String
  # @rbs return: Array[result]
  def items(values, item, limit, seen)
    none = [[], 0] #: [Array[result], Integer]
    coerced = values.each_with_index.reduce(none) do |state, (value, index)|
      done, count = state
      break state if count >= limit

      result = item.call(value, yield(index), seen)
      # Appended in place: copying the array for each item would be quadratic.
      [done << result, count + errors([result]).size]
    end
    coerced.first
  end

  # @rbs results: Array[result]
  # @rbs &: (Array[untyped]) -> untyped
  # @rbs return: result
  def collected(results)
    errors = errors(results)
    return Invalid.new(errors:) unless errors.empty?

    ok = results #: Array[Ok]
    Ok.new(value: yield(ok.map(&:value)))
  end

  # @rbs fields: Array[[Skyward::Types::Field, coercer]]
  # @rbs limit: Integer
  # @rbs expected: String?
  # @rbs &: (Hash[Symbol, untyped]) -> untyped
  # @rbs return: coercer
  def object(fields, limit, expected, &)
    lambda do |raw, at, seen|
      next mismatch(expected, raw, at) unless raw.is_a?(Hash)

      none = [[], 0] #: [Array[[Symbol, result]], Integer]
      coerced = fields.reduce(none) do |state, (field, coercer)|
        done, count = state
        break state if count >= limit

        name = field.name.to_s
        found = "#{at}.#{name}"
        result =
          raw.key?(name) ? coercer.call(raw.fetch(name), found, seen) : absent(field.type, field.required, found)
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

  # @rbs coercers: Array[coercer]
  # @rbs member: bool
  # @rbs expected: String?
  # @rbs return: coercer
  def union(coercers, member, expected)
    fit = lambda do |raw, at, seen|
      coercers.lazy.map { |coercer| coercer.call(raw, at, seen) }.find { |result| result.is_a?(Ok) } ||
        mismatch(expected, raw, at)
    end
    return fit unless member

    # Overlapping members, such as two records with the same field, each coerce
    # the same value as the same nested union, which costs 2^depth unless the
    # first result is kept. A member's result doesn't depend on where it is.
    ->(raw, at, seen) { seen[[fit.__id__, raw.__id__]] ||= fit.call(raw, at, seen) }
  end

  # @rbs results: Array[result]
  # @rbs return: Array[Error]
  def errors(results) = results.flat_map { |result| result.is_a?(Invalid) ? result.errors : [] }

  # @rbs type: Skyward::Types::t
  # @rbs return: String
  def expectation(type)
    cut(type.is_a?(Skyward::Types::Scalar) ? FORMATS.fetch(type.name) { written(type) } : written(type))
  end

  # @rbs text: String
  # @rbs return: String
  def cut(text) = text.length > MAX_SHOWN ? "#{text[0, MAX_SHOWN - 1]}…" : text

  # @rbs expected: String?
  # @rbs raw: untyped
  # @rbs at: String
  # @rbs return: Invalid
  def mismatch(expected, raw, at)
    return MISFIT unless expected

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
    when Skyward::Types::HashOf then "Hash[String, #{written(type.type)}]"
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
