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
      Skyward::ORM::Connection::Pool.new(1, -> { sqlite.connect(":memory:") }),
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

  describe "#check?" do
    it "is on" do
      assert_predicate session, :check?
    end
  end

  describe "#without_check" do
    it "turns the check off for the block" do
      refute(session.without_check { session.check? })
    end

    it "returns the block's value" do
      assert_equal(:booted, session.without_check { :booted })
    end

    it "turns it back on afterwards" do
      session.without_check { nil }

      assert_predicate session, :check?
    end

    it "turns it back on when the block raises" do
      assert_raises(Skyward::Core::BootError) { session.without_check { raise Skyward::Core::BootError } }

      assert_predicate session, :check?
    end
  end
end
