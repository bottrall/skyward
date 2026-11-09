# frozen_string_literal: true

module Skyward::ORM::Migrations
  AddColumns = Data.define(
    :klass, #: singleton(Skyward::ORM::Record)
    :columns #: Array[Skyward::ORM::Tables::Column]
  )
end
