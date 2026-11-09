# frozen_string_literal: true

module Skyward::ORM::Tables
  Reference = Data.define(
    :column, #: Symbol
    :table, #: singleton(Skyward::ORM::Record)
    :on_delete #: on_delete?
  )
end
