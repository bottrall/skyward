# frozen_string_literal: true

module Skyward::ORM::Migrations
  DropConstraint = Data.define(
    :constraint #: Skyward::ORM::Catalog::Constraint
  )
end
