# frozen_string_literal: true

module Skyward::ORM::Migrations
  ChangeDefault = Data.define(
    :column, #: Symbol
    :from, #: String?
    :to #: String?
  )
end
