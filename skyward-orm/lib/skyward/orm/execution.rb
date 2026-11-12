# frozen_string_literal: true

module Skyward::ORM
  Execution = Data.define(
    :sql, #: String
    :binds, #: Array[untyped]
    :adapter #: Symbol
  )
end
