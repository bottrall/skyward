# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Adapters::PostgreSQL::Connection do
  let(:connection) { TestDatabase.empty('postgresql').connect }

  describe '#execute' do
    it "returns each row's values, bound to numbered placeholders" do
      assert_equal [%w[Milk 2]], connection.execute('SELECT $1::text, $2::bigint', ['Milk', 2])
    end

    it 'runs SQL with nothing to bind' do
      assert_equal [['1']], connection.execute('SELECT 1')
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
