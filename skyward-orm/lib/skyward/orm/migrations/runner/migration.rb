# frozen_string_literal: true

module Skyward::ORM::Migrations::Runner
  Migration = Data.define(
    :file, #: String
    :version, #: String
    :up, #: String
    :checksum #: String
  )
end
