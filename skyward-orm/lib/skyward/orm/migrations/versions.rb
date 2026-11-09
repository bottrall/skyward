# frozen_string_literal: true

module Skyward::ORM::Migrations::Versions
  extend self

  # Running a migration records its version here, and a database that's
  # never been migrated doesn't have the table yet.
  TABLE = :schema_migrations #: Symbol

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs return: Hash[String, String]
  def checksums(database)
    return {} unless database.tables.any? { |table| table.name == TABLE }

    database.execute("SELECT version, checksum FROM #{TABLE}").to_h do |version, checksum|
      [version.to_s, checksum.to_s]
    end
  end
end
