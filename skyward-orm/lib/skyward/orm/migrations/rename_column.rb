# frozen_string_literal: true

module Skyward::ORM::Migrations
  RenameColumn = Data.define(
    :from, #: Symbol
    :to #: Symbol
  )
end
