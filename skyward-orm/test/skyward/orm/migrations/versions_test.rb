# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Migrations::Versions do
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  column_types = Skyward::ORM::Tables::ColumnTypes.new(
    Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))
  )

  let(:empty) { TestDatabase.empty }
  let(:connection) { empty.connect }
  # Lazy, so it reads the schema a test has made.
  let(:database) do
    Skyward::ORM::Connection::Database.new(
      empty.adapter,
      Skyward::ORM::Connection::Pool.new(1, -> { connection }),
      column_types,
      empty.adapter.tables(connection),
      check: false
    )
  end

  describe ".ran" do
    it "has none on a database that's never been migrated" do
      assert_empty Skyward::ORM::Migrations::Versions.ran(database)
    end

    it "reads each version that's run, as text" do
      connection.execute("CREATE TABLE schema_migrations (version #{empty.adapter.sql_type(:integer)} PRIMARY KEY)")
      connection.execute("INSERT INTO schema_migrations (version) VALUES (20261018093000)")

      assert_equal ["20261018093000"], Skyward::ORM::Migrations::Versions.ran(database)
    end
  end
end
