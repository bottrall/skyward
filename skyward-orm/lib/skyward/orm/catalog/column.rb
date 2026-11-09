# frozen_string_literal: true

module Skyward::ORM::Catalog
  Column = Data.define(
    :name, #: Symbol
    :type, #: String
    :nullable, #: bool
    # The SQL that follows DEFAULT, as a migration writes it, so a class's
    # default compares with it as text.
    :default #: String?
  )
end
