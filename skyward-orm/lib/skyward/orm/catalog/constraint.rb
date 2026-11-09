# frozen_string_literal: true

module Skyward::ORM::Catalog
  Constraint = Data.define(
    :name, #: String?
    :kind, #: constraint_kind
    :columns, #: Array[Symbol]
    :references, #: Symbol?
    # What follows its name as a table constraint, such as
    # "FOREIGN KEY (list_id) REFERENCES lists", so a migration can put it back.
    :definition #: String
  )
end
