# frozen_string_literal: true

module Skyward::ORM::Tables::Validation
  extend self

  # A declaration can come before the attr_reader that defines its column, so
  # the columns it names are checked once the class has loaded.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: void
  def validate(klass)
    schema = klass.schema
    named = [
      [:primary_key, schema.primary_key],
      *schema.references.map { |reference| [:references, reference.column] },
      *schema.defaults.keys.map { |column| [:default, column] },
      *schema.uniques.flatten.map { |column| [:unique, column] },
      *schema.checks.map { |check| [:check, check.column] },
      *schema.indexes.flatten.map { |column| [:index, column] }
    ] #: Array[[Symbol, Symbol]]
    unknown = named.reject { |_, column| schema.columns.include?(column) }.uniq
    return if unknown.empty?

    problems = unknown.map do |declaration, column|
      "#{klass} has no column #{column}, which its #{declaration} names. " \
        "Add `attr_reader :#{column}`, or fix the name."
    end
    raise Skyward::Core::BootError, problems.join("\n")
  end
end
