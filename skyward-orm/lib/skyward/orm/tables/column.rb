# frozen_string_literal: true

module Skyward::ORM::Tables
  Column = Data.define(
    :name, #: Symbol
    :type, #: column_type
    :nullable, #: bool
    :symbols #: Array[Symbol]
  )
end
