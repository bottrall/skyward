# frozen_string_literal: true

module Skyward::ORM::Catalog
  Table = Data.define(
    :name, #: Symbol
    :columns, #: Array[Column]
    :indexes, #: Array[Index]
    :constraints #: Array[Constraint]
  )
end
