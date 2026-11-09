# frozen_string_literal: true

module Skyward::ORM::Tables::Rows
  extend self

  METHODS = %i[initialize_columns to_h == eql? hash].freeze #: Array[Symbol]

  # Each row sets, compares and hashes its columns' instance variables
  # directly, rather than reflecting on them for every row.
  # @rbs columns: Array[Symbol]
  # @rbs return: String
  def source(columns)
    mismatch = "raise ArgumentError, Skyward::ORM::Tables::Rows.mismatch(self.class, #{columns.inspect}, columns.keys)"
    <<~RUBY
      private def initialize_columns(columns)
        #{columns.map { |column| "@#{column} = columns.fetch(#{column.inspect}) { #{mismatch} }" }.join("\n")}
        #{mismatch} unless columns.size == #{columns.size}
      end

      def to_h = { #{columns.map { |column| "#{column}: @#{column}" }.join(", ")} }

      def ==(other) = #{compare(columns, "==")}

      def eql?(other) = #{compare(columns, "eql?")}

      def hash = [#{["self.class", *columns.map { |column| "@#{column}" }].join(", ")}].hash
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
      ("is missing #{missing.join(", ")}" unless missing.empty?),
      ("has no column #{unknown.join(", ")}" unless unknown.empty?)
    ]
    "#{klass} #{problems.compact.join(", and ")}"
  end

  private

  # @rbs columns: Array[Symbol]
  # @rbs method: String
  # @rbs return: String
  def compare(columns, method)
    ["other.instance_of?(self.class)", *columns.map { |column| "@#{column}.#{method}(other.#{column})" }].join(" && ")
  end
end
