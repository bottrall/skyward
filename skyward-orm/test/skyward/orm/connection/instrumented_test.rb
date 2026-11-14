# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Connection::Instrumented do
  instrumented = Skyward::ORM::Connection::Instrumented

  let(:empty) { TestDatabase.empty }
  let(:connection) { empty.connect.tap { |connection| connection.execute('CREATE TABLE lists (name TEXT)') } }
  let(:executions) { [] }
  let(:durations) { [] }
  let(:passing) do
    lambda do |execution, &run|
      executions << execution
      durations << run.call
      :ignored
    end
  end

  def wrap(instrument, clock_ms: -> { 0.0 })
    Skyward::ORM::Connection::Instrumented.new(connection, instrument, :test, clock_ms:)
  end

  def execution(sql, binds = []) = Skyward::ORM::Execution.new(sql:, binds:, adapter: :test)

  def names = connection.execute('SELECT name FROM lists')

  describe '#execute' do
    it 'reports the statement, runs it when the instrument calls its block, and returns its rows' do
      insert = empty.shown('INSERT INTO lists (name) VALUES (?)', ['Home']).fetch(0)
      select = 'SELECT name FROM lists'
      wrapped = wrap(passing)
      wrapped.execute(insert, ['Home'])

      assert_equal [[['Home']], [execution(insert, ['Home']), execution(select)]], [wrapped.execute(select), executions]
    end
  end

  describe '#execute2' do
    it 'reports the statement with its binds, and returns the column names and rows' do
      sql = empty.shown('SELECT ? AS name', ['Home']).fetch(0)

      assert_equal [[['name'], ['Home']], [execution(sql, ['Home'])]], [wrap(passing).execute2(sql, 'Home'), executions]
    end
  end

  describe '#execute_batch' do
    it 'reports every statement in the SQL as one, with no binds' do
      sql = "INSERT INTO lists (name) VALUES ('Home'); INSERT INTO lists (name) VALUES ('Work');"
      wrap(passing).execute_batch(sql)

      assert_equal [[['Home'], ['Work']], [execution(sql)]], [names, executions]
    end
  end

  describe '#changes' do
    it "is the connection's count for its latest write" do
      wrapped = wrap(passing)
      wrapped.execute("INSERT INTO lists (name) VALUES ('Home'), ('Work')")

      assert_equal 2, wrapped.changes
    end
  end

  describe '#transaction_active?' do
    it "is the connection's" do
      wrapped = wrap(passing)
      wrapped.execute('BEGIN')

      assert_predicate wrapped, :transaction_active?
    end
  end

  describe '#close' do
    it 'closes the connection' do
      wrap(passing).close

      assert_raises(StandardError) { names }
    end
  end

  describe 'the instrument' do
    it "can't change the statement it's given, which runs as sent" do
      sql = +empty.shown('INSERT INTO lists (name) VALUES (?)', ['Home']).fetch(0)
      binds = ['Home']
      instrument = lambda do |execution, &run|
        assert_raises(FrozenError) { execution.sql.replace('DELETE FROM lists') }
        assert_raises(FrozenError) { execution.binds.replace(['Work']) }
        run.call
      end
      wrap(instrument).execute(sql, binds)

      assert_equal [[['Home']], false, false], [names, sql.frozen?, binds.frozen?]
    end

    it "is given the statement's duration in milliseconds, read from the clock before and after it" do
      readings = [10.0, 12.5]
      wrap(passing, clock_ms: -> { readings.shift }).execute('SELECT 1')

      assert_equal [2.5], durations
    end

    it 'runs on the fiber that runs the statement' do
      fibers = []
      instrument = lambda do |_execution, &run|
        fibers << Fiber.current
        run.call
      end
      wrap(instrument).execute('SELECT 1')

      assert_equal [Fiber.current], fibers
    end

    it 'sees the error of a statement that fails, which raises through it' do
      seen = []
      instrument = lambda do |_execution, &run|
        run.call
      rescue StandardError => e
        seen << e
        raise
      end
      error = assert_raises(StandardError) { wrap(instrument).execute('SELECT * FROM missing') }

      assert_equal [error], seen
    end

    it 'runs nothing when it raises before calling its block' do
      instrument = ->(_execution) { raise IOError, 'refused' }
      error = assert_raises(IOError) { wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')") }

      assert_equal ['refused', []], [error.message, names]
    end

    it 'keeps what the statement did when it raises after calling its block' do
      instrument = lambda do |_execution, &run|
        run.call
        raise IOError, 'refused'
      end
      assert_raises(IOError) { wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')") }

      assert_equal [['Home']], names
    end

    it 'raises at a second call of its block, which runs nothing' do
      instrument = lambda do |_execution, &run|
        run.call
        run.call
      end
      error = assert_raises(RuntimeError) { wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')") }

      assert_equal [instrumented::ONCE, [['Home']]], [error.message, names]
    end

    it 'raises without running the statement when it never calls its block' do
      error = assert_raises(RuntimeError) do
        wrap(->(_execution) {}).execute("INSERT INTO lists (name) VALUES ('Home')")
      end

      assert_equal [instrumented::ONCE, []], [error.message, names]
    end
  end
end
