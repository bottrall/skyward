# frozen_string_literal: true

module Skyward::ORM::Migrations
  # A table that differs from its class: the class's columns, the table as the
  # database has it, each difference, in the order the migration makes them,
  # and the indexes and constraints the table keeps because the class can't
  # declare them.
  AlterTable = Data.define(
    :klass, #: singleton(Skyward::ORM::Record)
    :columns, #: Array[Skyward::ORM::Tables::Column]
    :table, #: Skyward::ORM::Catalog::Table
    :edits, #: Array[edit]
    :kept_indexes, #: Array[Skyward::ORM::Catalog::Index]
    :kept_constraints #: Array[Skyward::ORM::Catalog::Constraint]
  )
end
