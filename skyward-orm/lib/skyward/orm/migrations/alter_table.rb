# frozen_string_literal: true

module Skyward::ORM::Migrations
  # A table that differs from its class: the class's columns, the table as the
  # database has it, and each difference, in the order the migration makes them.
  AlterTable = Data.define(
    :klass, #: singleton(Skyward::ORM::Record)
    :columns, #: Array[Skyward::ORM::Tables::Column]
    :table, #: Skyward::ORM::Catalog::Table
    :edits #: Array[edit]
  )
end
