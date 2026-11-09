# frozen_string_literal: true

module Skyward::ORM::Migrations
  ChangeNullable = Data.define(
    :column, #: Symbol
    :nullable #: bool
  )
end
