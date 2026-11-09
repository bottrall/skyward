# frozen_string_literal: true

module Skyward::ORM
  # @rbs!
  #   type violation_kind = :unique | :foreign_key | :not_null | :check

  Violation = Data.define(
    :kind, #: violation_kind
    :constraint, #: String?
    :columns, #: Array[Symbol]
    :message #: String
  )
end
