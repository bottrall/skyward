# frozen_string_literal: true

require "test_helper"
require_relative "../fixtures/tables/tables_fixtures"

describe Skyward::ORM do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "registers its signatures, which an app's table classes subclass" do
    builder = Skyward::Core::Signatures.load(File.expand_path("missing", __dir__))

    assert builder.env.class_decl?(RBS::TypeName.parse("::Skyward::ORM::Record"))
  end
end

describe Skyward do
  describe ".connect" do
    fixtures = File.expand_path("../fixtures/tables", __dir__)
    todo = TablesFixtures::Todo
    values = [1, 1, "Buy milk", "normal", nil, 0, "2026-10-18 09:30:00.000000"]

    it "keeps the database it connects to, for every query" do
      database = Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"), check: false)

      assert_same database, Skyward::ORM::Connection::SESSION.database
    end

    it "reads column types from the signatures given" do
      database = Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"), check: false)

      assert_equal :normal, database.decoder(todo, todo).call(values).priority
    end

    it "reads them from sig/ in the current directory by default" do
      database = Dir.chdir(fixtures) { Skyward.connect("sqlite://:memory:", check: false) }

      assert_equal :normal, database.decoder(todo, todo).call(values).priority
    end

    # Other tests' table classes are loaded too, so this looks only for one of its own.
    it "checks every loaded table class against the schema" do
      error = assert_raises(Skyward::ORM::SchemaMismatch) do
        Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))
      end

      assert_includes error.message, "TablesFixtures::Todo doesn't match the todos table"
    end

    it "connects with the check off inside the session's without_check" do
      database = Skyward::ORM::Connection::SESSION.without_check do
        Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))
      end

      assert_same database, Skyward::ORM::Connection::SESSION.database
    end

    it "doesn't keep a database that doesn't match" do
      kept = Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"), check: false)
      assert_raises(Skyward::ORM::SchemaMismatch) do
        Skyward.connect("sqlite://:memory:", signatures: File.join(fixtures, "sig"))
      end

      assert_same kept, Skyward::ORM::Connection::SESSION.database
    end
  end

  describe ".sql" do
    it "wraps an SQL expression" do
      assert_equal Skyward::ORM::Tables::SQL.new(expression: "now()"), Skyward.sql("now()")
    end

    it "keeps a frozen copy" do
      assert_predicate Skyward.sql(+"now()").expression, :frozen?
    end

    it "refuses anything but a String" do
      error = assert_raises(ArgumentError) { Skyward.sql(:now) }

      assert_equal "Skyward.sql takes the SQL as a String, not :now", error.message
    end
  end
end
