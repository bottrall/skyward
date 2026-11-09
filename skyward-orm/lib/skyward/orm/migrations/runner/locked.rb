# frozen_string_literal: true

module Skyward::ORM::Migrations::Runner
  Locked = Data.define(
    :file, #: String
    :message #: String
  )
end
