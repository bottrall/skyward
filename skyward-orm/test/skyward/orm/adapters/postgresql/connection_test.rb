# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Adapters::PostgreSQL::Connection do
  select = 'SELECT $1::integer + 1'
  insert = 'INSERT INTO lists (name) VALUES ($1)'
  ids = 'SELECT id FROM lists'

  let(:statements) { Skyward::ORM::Adapters::StatementCache.new }
  let(:connection) do
    url = TestDatabase.empty('postgresql').url
    Skyward::ORM::Adapters::PostgreSQL::Connection.new(PG.connect(url), statements)
  end

  def prepared = connection.execute('SELECT name, statement FROM pg_prepared_statements ORDER BY name')

  def error
    yield
  rescue PG::Error => e
    [e.class, e.message]
  end

  def placeholders(count) = "SELECT #{(1..count).map { |position| "$#{position}::integer" }.join(', ')}"

  describe '#execute' do
    it "returns each row's values, bound to numbered placeholders" do
      assert_equal [%w[Milk 2]], connection.execute('SELECT $1::text, $2::bigint', ['Milk', 2])
    end

    it 'runs SQL with nothing to bind' do
      assert_equal [['1']], connection.execute('SELECT 1')
    end

    it "prepares nothing it isn't asked to" do
      connection.execute(select, [1])

      assert_empty prepared
    end

    it 'keeps a statement with 100 values' do
      connection.execute(placeholders(100), Array.new(100, 1), prepare: true)

      assert_equal ['skyward_1'], prepared.map(&:first)
    end

    it "doesn't keep one with more" do
      connection.execute(placeholders(101), Array.new(101, 1), prepare: true)

      assert_empty prepared
    end

    it "prepares a statement it's asked to, named from its counter, and keeps it" do
      connection.execute(select, [1], prepare: true)

      assert_equal [['skyward_1', select]], prepared
    end

    it 'runs a kept statement again, with the values bound this time' do
      connection.execute(select, [1], prepare: true)

      assert_equal [['3']], connection.execute(select, [2], prepare: true)
    end

    it 'prepares a statement once, however many times it runs' do
      2.times { |number| connection.execute(select, [number], prepare: true) }

      assert_equal [['2']], connection.execute('SELECT generic_plans + custom_plans FROM pg_prepared_statements')
    end

    it "doesn't keep a statement whose prepare fails" do
      error { connection.execute('SELEC 1', prepare: true) }

      assert_nil statements.fetch('SELEC 1')
    end

    describe 'with its cache full' do
      let(:statements) { Skyward::ORM::Adapters::StatementCache.new(1) }

      it 'deallocates the least recently used statement once it has prepared another' do
        connection.execute('SELECT 1', prepare: true)
        connection.execute('SELECT 2', prepare: true)

        assert_equal [['skyward_2', 'SELECT 2']], prepared
      end

      it 'prepares another once DISCARD ALL has dropped the one it evicts' do
        connection.execute('SELECT 1', prepare: true)
        connection.execute_batch('DISCARD ALL')

        assert_equal [['2']], connection.execute('SELECT 2', prepare: true)
      end

      it 'prepares another in a transaction once DISCARD ALL has dropped the one it evicts, leaving it usable' do
        connection.execute('SELECT 1', prepare: true)
        connection.execute_batch('DISCARD ALL')
        connection.execute('BEGIN')
        rows = connection.execute('SELECT 2', prepare: true)

        assert_equal [[['2']], [['3']]], [rows, connection.execute('SELECT 3')]
      end

      it 'evicts nothing in a transaction already aborted, which refuses to prepare' do
        connection.execute('SELECT 1', prepare: true)
        connection.execute('BEGIN')
        error { connection.execute('SELECT 1 / 0') }
        error { connection.execute('SELECT 2', prepare: true) }
        connection.execute('ROLLBACK')

        assert_equal [['skyward_1', 'SELECT 1']], prepared
      end
    end

    it 'keeps a statement through a rollback' do
      connection.execute('BEGIN')
      connection.execute(select, [1], prepare: true)
      connection.execute('ROLLBACK')
      connection.execute(select, [2], prepare: true)

      assert_equal [['skyward_1', select]], prepared
    end

    describe 'with a table' do
      before do
        connection.execute_batch(<<~SQL)
          CREATE TABLE lists (id integer, name text UNIQUE);
          INSERT INTO lists VALUES (1, 'Home');
        SQL
      end

      it 'keeps a statement whose run fails' do
        error { connection.execute(insert, ['Home'], prepare: true) }

        assert_equal 'skyward_1', statements.fetch(insert)
      end

      it "raises the error a statement it doesn't keep raises" do
        unkept = error { connection.execute(insert, ['Home']) }

        assert_equal(unkept, error { connection.execute(insert, ['Home'], prepare: true) })
      end

      it 'keeps its statements when a kept one raises another error of SQLSTATE 0A000' do
        connection.execute_batch(<<~SQL)
          CREATE FUNCTION unsupported() RETURNS integer LANGUAGE plpgsql
          AS $$ BEGIN RAISE EXCEPTION 'unsupported' USING ERRCODE = 'feature_not_supported'; END $$
        SQL
        2.times { error { connection.execute('SELECT unsupported()', prepare: true) } }

        assert_equal [['skyward_1', 'SELECT unsupported()']], prepared
      end

      it 'prepares a statement again that DISCARD ALL dropped' do
        connection.execute(ids, prepare: true)
        connection.execute_batch('DISCARD ALL')

        assert_equal [['1']], connection.execute(ids, prepare: true)
      end

      describe 'after a migration changes a column a kept statement returns' do
        before do
          connection.execute(ids, prepare: true)
          connection.execute(select, [1], prepare: true)
          connection.execute_batch('ALTER TABLE lists ALTER COLUMN id TYPE text')
        end

        it 'prepares it again and runs it outside a transaction' do
          assert_equal [['1']], connection.execute(ids, prepare: true)
        end

        it 'forgets and deallocates every statement it kept, outside a transaction' do
          connection.execute(ids, prepare: true)

          assert_equal [['skyward_3', ids]], prepared
        end

        it 'raises inside a transaction, which PostgreSQL has aborted' do
          connection.execute('BEGIN')

          assert_raises(PG::FeatureNotSupported) { connection.execute(ids, prepare: true) }
        end

        it 'forgets every statement it kept inside a transaction' do
          connection.execute('BEGIN')
          error { connection.execute(ids, prepare: true) }

          assert_nil statements.fetch(select)
        end

        it 'prepares it again once the transaction has rolled back' do
          connection.execute('BEGIN')
          error { connection.execute(ids, prepare: true) }
          connection.execute('ROLLBACK')

          assert_equal [['1']], connection.execute(ids, prepare: true)
        end
      end
    end
  end

  describe '#changes' do
    it 'is 0 before anything runs' do
      assert_equal 0, connection.changes
    end

    it 'is how many rows the latest execute changed' do
      connection.execute_batch("CREATE TABLE lists (name text); INSERT INTO lists VALUES ('Home'), ('Work');")
      connection.execute('UPDATE lists SET name = $1', ['Away'])
      updated = connection.changes
      connection.execute('DELETE FROM lists WHERE name = $1', ['Home'])

      assert_equal [2, 0], [updated, connection.changes]
    end
  end

  describe '#execute2' do
    it "returns the column names, then each row's values" do
      assert_equal [%w[title done], %w[Milk t]],
                   connection.execute2('SELECT $1::text AS title, $2::boolean AS done', 'Milk', true)
    end

    it 'names the columns when there are no rows' do
      assert_equal [['title']], connection.execute2("SELECT 'Milk' AS title WHERE false")
    end

    it "keeps a statement it's asked to prepare, and returns its column names and rows" do
      connection.execute2('SELECT $1::text AS title', 'Milk', prepare: true)

      assert_equal [['title'], ['Tea']], connection.execute2('SELECT $1::text AS title', 'Tea', prepare: true)
    end
  end

  describe '#execute_batch' do
    it 'runs every statement in the SQL' do
      connection.execute_batch("CREATE TABLE lists (name text); INSERT INTO lists VALUES ('Home');")

      assert_equal [['Home']], connection.execute('SELECT name FROM lists')
    end
  end

  describe '#transaction_active?' do
    it 'is false when the session is idle' do
      refute_predicate connection, :transaction_active?
    end

    it 'is true inside a transaction' do
      connection.execute('BEGIN')

      assert_predicate connection, :transaction_active?
    end
  end

  describe '#close' do
    it 'ends the session' do
      connection.close

      assert_raises(PG::ConnectionBad) { connection.execute('SELECT 1') }
    end
  end
end
