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

    it "asks the connection to keep the statement only when it's asked to" do
      prepared = []
      preparing = TestDatabase::Preparing.new(connection:, prepared:)
      wrapped = instrumented.new(preparing, passing, :test, clock_ms: -> { 0.0 })
      wrapped.execute('SELECT 1')
      wrapped.execute('SELECT 1', prepare: true)

      assert_equal [['SELECT 1', false], ['SELECT 1', true]], prepared
    end
  end

  describe '#execute2' do
    it 'reports the statement with its binds, and returns the column names and rows' do
      sql = empty.shown('SELECT ? AS name', ['Home']).fetch(0)

      assert_equal [[['name'], ['Home']], [execution(sql, ['Home'])]], [wrap(passing).execute2(sql, 'Home'), executions]
    end

    it "asks the connection to keep the statement only when it's asked to" do
      prepared = []
      preparing = TestDatabase::Preparing.new(connection:, prepared:)
      wrapped = instrumented.new(preparing, passing, :test, clock_ms: -> { 0.0 })
      wrapped.execute2('SELECT 1')
      wrapped.execute2('SELECT 1', prepare: true)

      assert_equal [['SELECT 1', false], ['SELECT 1', true]], prepared
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
    describe "the statement it's given" do
      let(:sql) { +empty.shown('INSERT INTO lists (name) VALUES (?)', ['Home']).fetch(0) }
      let(:binds) { ['Home'] }

      before { wrap(passing).execute(sql, binds) }

      it "can't change its SQL" do
        assert_raises(FrozenError) { executions.fetch(0).sql.replace('DELETE FROM lists') }
      end

      it "can't change its binds" do
        assert_raises(FrozenError) { executions.fetch(0).binds.replace(['Work']) }
      end

      it "runs as sent, leaving the caller's SQL and binds unfrozen" do
        assert_equal [[['Home']], false, false], [names, sql.frozen?, binds.frozen?]
      end
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

    describe 'a statement that fails' do
      let(:seen) { [] }
      let(:instrument) do
        lambda do |_execution, &run|
          run.call
        rescue StandardError => e
          seen << e
          raise
        end
      end

      it 'raises its error through it' do
        assert_raises(StandardError) { wrap(instrument).execute('SELECT * FROM missing') }
      end

      it 'sees the error it raises' do
        error = begin
          wrap(instrument).execute('SELECT * FROM missing')
        rescue StandardError => e
          e
        end

        assert_equal [error], seen
      end
    end

    def insert_home(instrument, error_class)
      wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')")
    rescue error_class
      nil
    end

    describe 'when it raises before calling its block' do
      let(:instrument) { ->(_execution) { raise IOError, 'refused' } }

      it 'raises its error' do
        assert_raises_with_message(IOError, 'refused') do
          wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')")
        end
      end

      it 'runs nothing' do
        insert_home(instrument, IOError)

        assert_empty names
      end
    end

    describe 'when it raises after calling its block' do
      let(:instrument) do
        lambda do |_execution, &run|
          run.call
          raise IOError, 'refused'
        end
      end

      it 'raises its error' do
        assert_raises(IOError) { wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')") }
      end

      it 'keeps what the statement did' do
        insert_home(instrument, IOError)

        assert_equal [['Home']], names
      end
    end

    describe 'when it calls its block a second time' do
      let(:instrument) do
        lambda do |_execution, &run|
          run.call
          run.call
        end
      end

      it 'raises' do
        assert_raises_with_message(RuntimeError, instrumented::ONCE) do
          wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')")
        end
      end

      it 'runs nothing the second time' do
        insert_home(instrument, RuntimeError)

        assert_equal [['Home']], names
      end
    end

    describe 'when it never calls its block' do
      let(:instrument) { ->(_execution) {} }

      it 'raises' do
        assert_raises_with_message(RuntimeError, instrumented::ONCE) do
          wrap(instrument).execute("INSERT INTO lists (name) VALUES ('Home')")
        end
      end

      it "doesn't run the statement" do
        insert_home(instrument, RuntimeError)

        assert_empty names
      end
    end
  end
end
