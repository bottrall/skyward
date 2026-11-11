# frozen_string_literal: true

module Skyward::ORM::Migrations
  RenameConstraint = Data.define(
    :from, #: String
    :to #: String
  )
end
