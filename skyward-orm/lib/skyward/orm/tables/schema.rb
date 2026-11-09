# frozen_string_literal: true

module Skyward::ORM::Tables
  Schema = Data.define(
    :table, #: Symbol?
    :primary_key, #: Symbol
    :columns, #: Array[Symbol]
    :references, #: Array[Reference]
    :defaults, #: Hash[Symbol, untyped]
    :checks, #: Array[Check]
    :uniques, #: Array[Array[Symbol]]
    :indexes #: Array[Array[Symbol]]
  )
end
