# frozen_string_literal: true

module Skyward::ORM::Tables::Members
  extend self

  KEYWORDS = %i[keyreq key].freeze #: Array[Symbol]

  # @rbs row: Class
  # @rbs return: Array[Symbol]
  def of(row)
    # Steep can't narrow a type by respond_to?.
    return row.members if row.respond_to?(:members) # steep:ignore NoMethod

    row.instance_method(:initialize).parameters.filter_map { |kind, name| name if KEYWORDS.include?(kind) }
  end
end
