# frozen_string_literal: true

module Skyward::ORM::Catalog
  Column = Data.define(
    :name, #: Symbol
    :type, #: String
    :nullable #: bool
  )
end
