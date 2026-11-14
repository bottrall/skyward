# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Connection::Pool do
  pool_class = Skyward::ORM::Connection::Pool
  connection_class = Struct.new(:active, :sent, :closed) do
    def transaction_active? = active

    def execute(sql)
      sent << sql
      self.active = false
    end

    def close = self.closed = true
  end

  let(:opened) { [] }
  let(:opener) { -> { connection_class.new(false, [], false).tap { |connection| opened << connection } } }

  # Checking it in leaves a vacancy.
  def lose(connection)
    connection.active = true
    def connection.execute(_sql) = raise(IOError, 'connection lost')
    connection
  end

  describe '#with' do
    it 'opens nothing until a connection is asked for' do
      pool_class.new(2, opener)

      assert_empty opened
    end

    it "yields a connection it opens, and returns the block's value" do
      pool = pool_class.new(2, opener)
      value = pool.with { |connection| [:done, connection] }

      assert_equal [:done, opened.first], value
    end

    it 'takes a connection back when the block raises' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      assert_raises(RuntimeError) { pool.with { raise 'failed' } }

      assert_same(opened.first, pool.with { |connection| connection })
    end

    it 'reuses a connection that has come back rather than opening another' do
      pool = pool_class.new(2, opener)
      2.times { pool.with { |connection| connection } }

      assert_equal 1, opened.size
    end

    it 'opens another while the first is out' do
      pool = pool_class.new(2, opener)
      outer, inner = pool.with { |first| pool.with { |second| [first, second] } }

      refute_same outer, inner
    end

    it 'opens no more than its size, and waits for one to come back' do
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
      Thread.pass while waiter.status == 'run'
      release << true
      holder.join

      assert_same held, waiter.value
    end

    it 'gives up after its timeout, saying how long it waited for how many' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      error = assert_raises(Skyward::ORM::PoolTimeout) { pool.with { pool.with { nil } } }

      assert_equal 'Skyward ORM waited 0.01 seconds for a database connection, but all 1 in its pool stayed ' \
                   'in use. Pass Skyward.connect a larger pool:, or hold each connection for less time.',
                   error.message
    end

    it 'keeps no place for a connection that failed to open' do
      failures = [RuntimeError.new('refused')]
      pool = pool_class.new(1, -> { failures.empty? ? opener.call : raise(failures.pop) }, timeout: 0.01)
      assert_raises(RuntimeError) { pool.with { nil } }
      connection = pool.with { |opened_now| opened_now }

      assert_same opened.first, connection
    end
  end

  describe '#checkout' do
    it "opens a connection in a vacancy's place" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      pool.checkin(lose(pool.checkout))
      connection = pool.checkout

      assert_same opened.fetch(1), connection
    end

    it 'leaves the vacancy when the connection for it fails to open' do
      failures = []
      pool = pool_class.new(1, -> { failures.empty? ? opener.call : raise(failures.pop) }, timeout: 0.01)
      pool.checkin(lose(pool.checkout))
      failures << RuntimeError.new('refused')
      assert_raises(RuntimeError) { pool.checkout }
      connection = pool.checkout

      assert_same opened.last, connection
    end

    it 'wakes a checkout waiting for a connection with a vacancy, and opens one in its place' do
      pool = pool_class.new(1, opener)
      held = pool.checkout
      waiter = Thread.new { pool.checkout }
      Thread.pass while waiter.status == 'run'
      pool.checkin(lose(held))
      connection = waiter.value

      assert_same opened.fetch(1), connection
    end

    it "keeps a connection out until it's checked in" do
      pool = pool_class.new(1, opener, timeout: 0.01)
      pool.checkout

      assert_raises(Skyward::ORM::PoolTimeout) { pool.checkout }
    end
  end

  describe '#checkin' do
    it 'gives a connection back for the next checkout' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      pool.checkin(pool.checkout)

      assert_same opened.first, pool.checkout
    end

    it 'rolls back one that comes back mid-transaction, and gives it back' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      interrupted = pool.checkout
      interrupted.active = true
      pool.checkin(interrupted)

      assert_equal [true, ['ROLLBACK']], [pool.checkout.equal?(interrupted), interrupted.sent]
    end

    it 'closes one still mid-transaction after its rollback, leaving a vacancy' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      stuck = pool.checkout
      stuck.active = true
      def stuck.execute(_sql) = []
      pool.checkin(stuck)
      pool.checkout

      assert_equal [true, 2], [stuck.closed, opened.size]
    end

    it 'closes one whose rollback fails, leaving a vacancy' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      lost = lose(pool.checkout)
      pool.checkin(lost)
      pool.checkout

      assert_equal [true, 2], [lost.closed, opened.size]
    end

    it 'raises nothing when closing fails, and still leaves a vacancy' do
      pool = pool_class.new(1, opener, timeout: 0.01)
      broken = lose(pool.checkout)
      def broken.close = raise(IOError, 'connection lost')
      pool.checkin(broken)
      pool.checkout

      assert_equal 2, opened.size
    end
  end
end
