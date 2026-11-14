# frozen_string_literal: true

module Skyward::ORM::Statements::Placeholders
  extend self

  # A ? in a string, a quoted name or a comment is the SQL's own, so those
  # match whole and are kept. SQL escapes a quote by doubling it, which reads
  # here as two strings side by side.
  MARKS = %r{'[^']*'|"[^"]*"|--[^\n]*|/\*.*?\*/|\?}m #: Regexp

  # @rbs sql: String
  # @rbs count: Integer
  # @rbs &: (Integer position) -> String
  # @rbs return: String
  def replace(sql, count)
    marks = 0
    replaced = sql.gsub(MARKS) { |match| match == '?' ? yield(marks += 1) : match }
    return replaced if marks == count

    raise ArgumentError, "The SQL has #{marks} ?, each taking one value, but was given #{count}"
  end

  # The driver spreads an Array or Hash across several placeholders, or none,
  # moving every value after it to another `?`.
  # @rbs binds: Array[untyped]
  # @rbs subject: String
  # @rbs return: void
  def require_scalars(binds, subject)
    binds.each.with_index(1) do |bind, index|
      kind = case bind
             when Array then 'an Array'
             when Hash then 'a Hash'
             end
      raise ArgumentError, "#{subject} binds one value to each ?, but value #{index} is #{kind}" if kind
    end
  end
end
