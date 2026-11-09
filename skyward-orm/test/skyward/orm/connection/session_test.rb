# frozen_string_literal: true

require "test_helper"
require "sqlite3"

describe Skyward::ORM::Connection::Session do
  sqlite = Skyward::ORM::Adapters::SQLite
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(File.expand_path("missing", __dir__)))

  let(:session) { Skyward::ORM::Connection::Session.new }
  let(:database) do
    Skyward::ORM::Connection::Database.new(
      sqlite,
      sqlite.connect(":memory:"),
      Skyward::ORM::Tables::ColumnTypes.new(reader),
      [],
      check: true
    )
  end

  describe "#connect" do
    it "returns the database" do
      assert_same database, session.connect(database)
    end
  end

  describe "#database" do
    it "is the database connected" do
      session.connect(database)

      assert_same database, session.database
    end

    it "says to connect when nothing has" do
      error = assert_raises(Skyward::Core::BootError) { session.database }

      assert_equal "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots.", error.message
    end
  end
end
