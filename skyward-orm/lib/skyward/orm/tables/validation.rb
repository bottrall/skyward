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

    columns = schema.columns.map(&:to_s)
    problems = unknown.map do |declaration, column|
      message = "#{klass} has no column #{column}, which its #{declaration} names. " \
                "Add `attr_reader :#{column}`, or fix the name."
      # A column declared nowhere, as the default primary key is, has no line to point at.
      if klass.declared_at(declaration, column)
        spot = Skyward::ORM::Tables::Sources.declaration(klass, declaration, column)
        suggestion = Skyward::Core::Diagnostics::Suggestion.closest(column.to_s, columns)
        Skyward::ORM::Tables::Sources.explain(message, [spot], suggestion)
      else
        message
      end
    end
    raise Skyward::Core::BootError, Skyward::ORM::Tables::Sources.join(problems)
  end
end
