# frozen_string_literal: true

require "test_helper"
require "sqlite3"

describe Skyward::ORM::Migrations::Versions do
  sqlite = Skyward::ORM::Adapters::SQLite
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  column_types = Skyward::ORM::Tables::ColumnTypes.new(
    Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))
  )

  let(:connection) { sqlite.connect(":memory:") }
  # Lazy, so it reads the schema a test has made.
  let(:database) { Skyward::ORM::Connection::Database.new(sqlite, connection, column_types, sqlite.tables(connection), check: false) }

  describe ".ran" do
    it "has none on a database that's never been migrated" do
      assert_empty Skyward::ORM::Migrations::Versions.ran(database)
    end

    it "reads each version that's run, as text" do
      connection.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY)")
      connection.execute("INSERT INTO schema_migrations (version) VALUES (20261018093000)")

      assert_equal ["20261018093000"], Skyward::ORM::Migrations::Versions.ran(database)
    end
  end
end
