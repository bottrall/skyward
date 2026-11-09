# frozen_string_literal: true

module Skyward::ORM::Migrations::Runner
  Migration = Data.define(
    :file, #: String
    :version, #: String
    :up, #: String
    :down, #: String
    :checksum #: String
  )
end
