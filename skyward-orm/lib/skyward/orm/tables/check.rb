# frozen_string_literal: true

module Skyward::ORM::Tables
  Check = Data.define(
    :column, #: Symbol
    :rule #: SQL | Length
  )
end
