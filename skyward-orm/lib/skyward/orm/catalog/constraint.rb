# frozen_string_literal: true

module Skyward::ORM::Catalog
  Constraint = Data.define(
    :name, #: String?
    :kind, #: constraint_kind
    :columns, #: Array[Symbol]
    :references #: Symbol?
  )
end
