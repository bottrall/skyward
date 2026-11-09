# frozen_string_literal: true

module Skyward::ORM::Catalog
  Index = Data.define(
    :name, #: String
    :columns, #: Array[Symbol]
    :unique #: bool
  )
end
