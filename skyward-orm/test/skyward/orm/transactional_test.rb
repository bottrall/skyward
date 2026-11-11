# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Transactional do
  signatures = File.expand_path("../../fixtures/tables/sig", __dir__)
  insert = lambda do |name|
    database = Skyward::ORM::Connection::SESSION.database
    database.connection do |connection|
      connection.execute("INSERT INTO lists (name) VALUES (#{database.adapter.placeholder(1)})", [name])
    end
  end
  names = -> { Skyward::ORM::Connection::SESSION.database.execute("SELECT name FROM lists ORDER BY id") }

  let(:empty) { TestDatabase.empty }
  let(:database) { Skyward.connect(empty.url, signatures:, check: false) }

  before { database.execute("CREATE TABLE lists (id #{empty.primary_key}, name TEXT)") }

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

  describe "with a second database" do
    let(:second) { TestDatabase.empty(second: true) }
    let(:switched) { Skyward.connect(second.url, signatures:, check: false, default: false) }

    before { switched.execute("CREATE TABLE lists (id #{second.primary_key}, name TEXT)") }

    it "rolls back writes through Skyward.using with the test, and the default's too" do
      database = switched
      run_test do
        define_method(:example) do
          insert.call("Home")
          Skyward.using(database) { insert.call("Work") }
        end
      end

      assert_equal [[], []], [names.call, Skyward.using(switched) { names.call }]
    end
  end
end
