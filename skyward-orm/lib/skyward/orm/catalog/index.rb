# frozen_string_literal: true

module Skyward::ORM::Catalog
  Index = Data.define(
    :name, #: String
    :columns, #: Array[Symbol]
    :unique, #: bool
    # Its CREATE INDEX statement, so a migration can put it back.
    :definition #: String
  )
end
