# frozen_string_literal: true

module Skyward::ORM::Tables::Rows
  extend self

  METHODS = %i[initialize_columns load_columns to_h deconstruct_keys inspect == eql? hash].freeze #: Array[Symbol]

  # Each row sets, reads, compares and hashes its columns' instance variables
  # directly, rather than reflecting on them for every row.
  # @rbs columns: Array[Symbol]
  # @rbs return: String
  def source(columns)
    mismatch = "raise ArgumentError, Skyward::ORM::Tables::Rows.mismatch(self.class, #{columns.inspect}, columns.keys)"
    # A column may be named after a keyword, such as end, which can't name a parameter.
    values = columns.each_index.map { |index| "value#{index}" }
    <<~RUBY
      private def initialize_columns(columns)
        #{columns.map { |column| "@#{column} = columns.fetch(#{column.inspect}) { #{mismatch} }" }.join("\n")}
        #{mismatch} unless columns.size == #{columns.size}
      end

      # A decoder passes a value for each column, in order, so nothing is checked.
      private def load_columns(#{values.join(', ')})
        #{columns.zip(values).map { |column, value| "@#{column} = #{value}" }.join("\n")}
        freeze
      end

      def to_h = { #{columns.map { |column| "#{column}: @#{column}" }.join(', ')} }

      def deconstruct_keys(keys)
        return to_h unless keys

        found = {}
        #{columns.map { |column| "found[#{column.inspect}] = @#{column} if keys.include?(#{column.inspect})" }.join("\n")}
        found
      end

      def inspect = "#<\#{self.class} #{columns.map { |column| "#{column}=\#{@#{column}.inspect}" }.join(', ')}>"

      def ==(other) = #{compare(columns, '==')}

      def eql?(other) = #{compare(columns, 'eql?')}

      def hash = [#{['self.class', *columns.map { |column| "@#{column}" }].join(', ')}].hash
    RUBY
  end

  # @rbs klass: Class
  # @rbs columns: Array[Symbol]
  # @rbs given: Array[Symbol]
  # @rbs return: String
  def mismatch(klass, columns, given)
    missing = columns - given
    unknown = given - columns
    problems = [
      ("is missing #{missing.join(', ')}" unless missing.empty?),
      ("has no column #{unknown.join(', ')}" unless unknown.empty?)
    ]
    "#{klass} #{problems.compact.join(', and ')}"
  end

  private

  # @rbs columns: Array[Symbol]
  # @rbs method: String
  # @rbs return: String
  def compare(columns, method)
    ['other.instance_of?(self.class)', *columns.map { |column| "@#{column}.#{method}(other.#{column})" }].join(' && ')
  end
end
