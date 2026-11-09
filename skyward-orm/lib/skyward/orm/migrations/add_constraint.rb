# frozen_string_literal: true

module Skyward::ORM::Migrations
  AddConstraint = Data.define(
    :constraint #: Skyward::ORM::Catalog::Constraint
  )
end
