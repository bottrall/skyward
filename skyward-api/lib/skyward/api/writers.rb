# frozen_string_literal: true

# Time#iso8601 is core only from Ruby 3.4.
require "time"

module Skyward::API::Writers
  extend self

  Writer = Data.define(
    :name, #: String
    :fits, #: ^(untyped) -> bool
    :write #: ^(untyped, String) -> untyped
  )

  Misfit = Data.define(
    :at, #: String
    :expected, #: String
    :got #: String
  )

  # @rbs type: Skyward::Types::t
  # @rbs return: Writer
  def writer(type)
    case type
    when Skyward::Types::Scalar then scalar(type.name)
    when Skyward::Types::Literal then literal(type.value)
    when Skyward::Types::Enum then enum(type.symbols)
    when Skyward::Types::Nullable then nullable(type.type)
    when Skyward::Types::ArrayOf then array(writer(type.type))
    when Skyward::Types::Record then record(type.fields)
    when Skyward::Types::Named then named(type)
    when Skyward::Types::Union then union(type.types.map { |member| writer(member) })
    end
  end

  # @rbs members: Array[Writer]
  # @rbs return: Writer
  def union(members)
    name = members.map(&:name).join(" | ")
    Writer.new(
      name:,
      fits: ->(value) { members.any? { |member| member.fits.call(value) } },
      write: lambda do |value, at|
        fitting = members.select { |candidate| candidate.fits.call(value) }
        fitting.empty? ? misfit(name, value, at) : first_written(fitting, value, at)
      end
    )
  end

  # @rbs name: String
  # @rbs fits: ^(untyped) -> bool
  # @rbs write: ^(untyped, String) -> untyped
  # @rbs return: Writer
  def checked(name, fits, write)
    Writer.new(
      name:,
      fits:,
      write: lambda do |value, at|
        fits.call(value) ? write.call(value, at) : misfit(name, value, at)
      end
    )
  end

  private

  # @rbs fitting: Array[Writer]
  # @rbs value: untyped
  # @rbs at: String
  # @rbs failed: Misfit?
  # @rbs return: untyped
  def first_written(fitting, value, at, failed = nil)
    head, *rest = fitting
    return failed unless head

    written = head.write.call(value, at)
    written.is_a?(Misfit) ? first_written(rest, value, at, failed || written) : written
  end

  # @rbs name: Skyward::Types::scalar
  # @rbs return: Writer
  def scalar(name)
    case name
    when :integer then checked("Integer", ->(value) { value.is_a?(Integer) }, ->(value, _) { value })
    when :float then checked("Float", ->(value) { value.is_a?(Float) }, ->(value, _) { value })
    when :string then checked("String", ->(value) { value.is_a?(String) }, ->(value, _) { value })
    when :bool then checked("bool", ->(value) { [true, false].include?(value) }, ->(value, _) { value })
    when :date then checked("Date", ->(value) { value.is_a?(Date) }, ->(value, _) { date(value) })
    when :time then checked("Time", ->(value) { value.is_a?(Time) }, ->(value, _) { time(value) })
    when :untyped then Writer.new(name: "untyped", fits: ->(_) { true }, write: ->(value, at) { untyped(value, at) })
    end
  end

  # @rbs value: Skyward::Types::literal
  # @rbs return: Writer
  def literal(value)
    checked(value.inspect, ->(given) { value.eql?(given) }, ->(given, _) { given })
  end

  # @rbs symbols: Array[Symbol]
  # @rbs return: Writer
  def enum(symbols)
    checked(symbols.map(&:inspect).join(" | "), ->(value) { symbols.include?(value) }, ->(value, _) { value.name })
  end

  # @rbs type: Skyward::Types::t
  # @rbs return: Writer
  def nullable(type)
    inner = writer(type)
    grouped = type.is_a?(Skyward::Types::Union) || (type.is_a?(Skyward::Types::Enum) && type.symbols.size > 1)
    Writer.new(
      name: grouped ? "(#{inner.name})?" : "#{inner.name}?",
      fits: ->(value) { value.nil? || inner.fits.call(value) },
      write: ->(value, at) { value.nil? ? nil : inner.write.call(value, at) }
    )
  end

  # @rbs item: Writer
  # @rbs return: Writer
  def array(item)
    checked(
      "Array[#{item.name}]",
      ->(value) { value.is_a?(Array) },
      ->(value, at) { items(value.each_with_index.map { |entry, index| item.write.call(entry, "#{at}[#{index}]") }) }
    )
  end

  # @rbs fields: Array[Skyward::Types::Field]
  # @rbs return: Writer
  def record(fields)
    writers = fields.map { |field| [field, writer(field.type)] } #: Array[[Skyward::Types::Field, Writer]]
    declared = writers.map { |field, writer| "#{"?" unless field.required}#{field.name}: #{writer.name}" }
    checked(
      "{ #{declared.join(", ")} }",
      ->(value) { value.is_a?(Hash) },
      ->(value, at) { object(writers.filter_map { |field, writer| entry(field, writer, value, at) }) }
    )
  end

  # @rbs field: Skyward::Types::Field
  # @rbs writer: Writer
  # @rbs hash: Hash[untyped, untyped]
  # @rbs at: String
  # @rbs return: [Symbol, untyped]?
  def entry(field, writer, hash, at)
    name = field.name
    if hash.key?(name) then [name, writer.write.call(hash[name], "#{at}.#{name}")]
    elsif field.required then [name, Misfit.new(at: "#{at}.#{name}", expected: writer.name, got: "nothing")]
    end
  end

  # Only declared readers are called, never to_h, so nothing else the object holds is written.
  # @rbs type: Skyward::Types::Named
  # @rbs return: Writer
  def named(type)
    klass = type.klass
    writers = type.fields.map { |field| [field.name, writer(field.type)] } #: Array[[Symbol, Writer]]
    checked(
      type.name,
      ->(value) { value.is_a?(klass) },
      lambda do |value, at|
        object(writers.map { |name, writer| [name, writer.write.call(value.public_send(name), "#{at}.#{name}")] })
      end
    )
  end

  # strftime rather than iso8601, which writes a DateTime with its time.
  # @rbs value: Date
  # @rbs return: String
  def date(value) = value.strftime("%Y-%m-%d")

  # Six fractional digits, so a time read back from JSON equals the one written.
  # @rbs value: Time
  # @rbs return: String
  def time(value) = value.getutc.iso8601(6)

  # @rbs value: untyped
  # @rbs at: String
  # @rbs return: untyped
  def untyped(value, at)
    case value
    when nil, true, false, Integer, Float, String then value
    when Symbol then value.name
    when Date then date(value)
    when Time then time(value)
    when Hash then object(value.map { |key, item| [key, untyped(item, "#{at}.#{key}")] })
    when Array then items(value.each_with_index.map { |item, index| untyped(item, "#{at}[#{index}]") })
    else value.respond_to?(:to_h) ? untyped(value.to_h, at) : misfit("something with to_h", value, at)
    end
  end

  # @rbs written: Array[untyped]
  # @rbs return: untyped
  def items(written) = written.find { |item| item.is_a?(Misfit) } || written

  # @rbs pairs: Array[[untyped, untyped]]
  # @rbs return: untyped
  def object(pairs)
    misfit = pairs.find { |_, written| written.is_a?(Misfit) }
    misfit ? misfit.last : pairs.to_h
  end

  # Names a value by its class unless it's a scalar, so a message never carries a String or an object's fields.
  # @rbs expected: String
  # @rbs value: untyped
  # @rbs at: String
  # @rbs return: Misfit
  def misfit(expected, value, at)
    got =
      case value
      when nil, true, false, Symbol, Integer, Float then value.inspect
      else value.class.inspect
      end
    Misfit.new(at:, expected:, got:)
  end
end
