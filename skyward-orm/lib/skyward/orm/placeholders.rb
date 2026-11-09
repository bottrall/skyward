# frozen_string_literal: true

module Skyward::ORM::Placeholders
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
    replaced = sql.gsub(MARKS) { |match| match == "?" ? yield(marks += 1) : match }
    return replaced if marks == count

    raise ArgumentError, "The SQL has #{marks} ?, each taking one value, but was given #{count}"
  end
end
