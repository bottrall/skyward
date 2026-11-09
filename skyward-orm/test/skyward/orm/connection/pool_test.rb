# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Connection::Pool do
  pool_class = Skyward::ORM::Connection::Pool

  let(:opened) { [] }
  let(:opener) { -> { Object.new.tap { |connection| opened << connection } } }

  describe "#with" do
    it "opens nothing until a connection is asked for" do
      pool_class.new(2, opener)

      assert_empty opened
    end

    it "yields a connection it opens, and returns the block's value" do
      pool = pool_class.new(2, opener)
      value = pool.with { |connection| [:done, connection] }

      assert_equal [:done, opened.first], value
    end

    it "takes a connection back when the block raises" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      assert_raises(RuntimeError) { pool.with { raise "failed" } }

      assert_same(opened.first, pool.with { |connection| connection })
    end

    it "reuses a connection that has come back rather than opening another" do
      pool = pool_class.new(2, opener)
      2.times { pool.with { |connection| connection } }

      assert_equal 1, opened.size
    end

    it "opens another while the first is out" do
      pool = pool_class.new(2, opener)
      outer, inner = pool.with { |first| pool.with { |second| [first, second] } }

      refute_same outer, inner
    end

    it "opens no more than its size, and waits for one to come back" do
      pool = pool_class.new(1, opener)
      taken = Thread::Queue.new
      release = Thread::Queue.new
      holder = Thread.new do
        pool.with do |connection|
          taken << connection
          release.pop
        end
      end
      held = taken.pop
      waiter = Thread.new { pool.with { |connection| connection } }
      Thread.pass while waiter.status == "run"
      release << true
      holder.join

      assert_same held, waiter.value
    end

    it "gives up after its timeout, saying how long it waited for how many" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      error = assert_raises(Skyward::ORM::PoolTimeout) { pool.with { pool.with { nil } } }

      assert_equal "Skyward ORM waited 0.01 seconds for a database connection, but all 1 in its pool stayed " \
                   "in use. Pass Skyward.connect a larger pool:, or hold each connection for less time.",
                   error.message
    end

    it "keeps no place for a connection that failed to open" do
      failures = [RuntimeError.new("refused")]
      pool = pool_class.new(1, -> { failures.empty? ? opener.call : raise(failures.pop) }, timeout: 0.01)
      assert_raises(RuntimeError) { pool.with { nil } }
      connection = pool.with { |opened_now| opened_now }

      assert_same opened.first, connection
    end
  end

  describe "#checkout" do
    it "keeps a connection out until it's checked in" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      pool.checkout

      assert_raises(Skyward::ORM::PoolTimeout) { pool.checkout }
    end
  end

  describe "#checkin" do
    it "gives a connection back for the next checkout" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      pool.checkin(pool.checkout)

      assert_same opened.first, pool.checkout
    end
  end
end
