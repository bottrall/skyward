# frozen_string_literal: true

module Skyward::ORM::Migrations
  DropColumn = Data.define(
    :column #: Skyward::ORM::Catalog::Column
  )
end
