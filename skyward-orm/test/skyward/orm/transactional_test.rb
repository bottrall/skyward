# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Transactional do
  signatures = File.expand_path("../../fixtures/tables/sig", __dir__)
  insert = lambda do |name|
    Skyward::ORM::Connection::SESSION.database.connection do |connection|
      connection.execute("INSERT INTO lists (name) VALUES (?)", [name])
    end
  end
  names = -> { Skyward::ORM::Connection::SESSION.database.execute("SELECT name FROM lists ORDER BY id") }

  let(:database) { Skyward.connect("sqlite://:memory:", signatures:, check: false) }

  before { database.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT)") }

  # Not named test_*, so Minitest never runs it as a test of its own.
  def run_test(&body)
    test = Class.new(Minitest::Spec, &body)
    test.include(Skyward::ORM::Transactional)
    test.new(:example).run
  end

  describe "#before_setup" do
    it "rolls back rows from before and let blocks with the test" do
      run_test do
        let(:list) { insert.call("Home") }
        before { insert.call("Work") }
        define_method(:example) { list }
      end

      assert_empty names.call
    end
  end

  describe "#after_teardown" do
    it "rolls back after a test that passed" do
      run_test { define_method(:example) { insert.call("Work") } }

      assert_empty names.call
    end

    it "rolls back after a test that failed" do
      run_test do
        define_method(:example) do
          insert.call("Work")

          flunk
        end
      end

      assert_empty names.call
    end

    it "rolls back after a test that raised" do
      run_test do
        define_method(:example) do
          insert.call("Work")
          raise "failed"
        end
      end

      assert_empty names.call
    end

    it "rolls back when an after_teardown it calls raises" do
      run_test do
        include(Module.new { define_method(:after_teardown) { raise "failed" } })

        define_method(:example) { insert.call("Work") }
      end

      assert_empty names.call
    end
  end
end
