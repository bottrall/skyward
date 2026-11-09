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
  let(:database) do
    Skyward::ORM::Connection::Database.new(
      sqlite,
      Skyward::ORM::Connection::Pool.new(1, -> { connection }),
      column_types,
      sqlite.tables(connection),
      check: false
    )
  end

  describe ".checksums" do
    it "has none on a database that's never been migrated, without making schema_migrations" do
      assert_equal [{}, []], [Skyward::ORM::Migrations::Versions.checksums(database), sqlite.tables(connection)]
    end

    it "reads each version that's run with its checksum, as text" do
      connection.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, checksum TEXT NOT NULL)")
      connection.execute("INSERT INTO schema_migrations (version, checksum) VALUES (20261018093000, 'abc')")

      assert_equal({ "20261018093000" => "abc" }, Skyward::ORM::Migrations::Versions.checksums(database))
    end
  end
end
