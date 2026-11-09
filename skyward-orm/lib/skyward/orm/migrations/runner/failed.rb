# frozen_string_literal: true

module Skyward::ORM::Migrations::Runner
  Failed = Data.define(
    :file, #: String
    :message #: String
  )
end
