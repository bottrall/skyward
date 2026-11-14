# frozen_string_literal: true

require 'test_helper'
require 'sqlite3'

describe Skyward::ORM::Adapters::SQLite::Connection do
  select = 'SELECT ? + 1'

  let(:statements) { Skyward::ORM::Adapters::StatementCache.new }
  let(:database) do
    SQLite3::Database.new(':memory:').tap do |database|
      database.extended_result_codes = true
      database.execute('CREATE TABLE lists (name TEXT UNIQUE)')
    end
  end
  let(:connection) { Skyward::ORM::Adapters::SQLite::Connection.new(database, statements) }

  def kept(sql) = statements.fetch(sql)

  def error
    yield
  rescue SQLite3::Exception => e
    [e.class, e.code]
  end

  describe '#execute' do
    it "returns each row's values, bound to ? placeholders" do
      assert_equal [['Milk', 2]], connection.execute('SELECT ?, ?', ['Milk', 2])
    end

    it "keeps nothing it isn't asked to prepare" do
      connection.execute(select, [1])

      assert_nil kept(select)
    end

    it 'keeps a statement with 100 values' do
      sql = "SELECT #{Array.new(100, '?').join(', ')}"
      connection.execute(sql, Array.new(100, 1), prepare: true)

      refute_nil kept(sql)
    end

    it "doesn't keep one with more" do
      sql = "SELECT #{Array.new(101, '?').join(', ')}"
      connection.execute(sql, Array.new(101, 1), prepare: true)

      assert_nil kept(sql)
    end

    it "keeps a statement it's asked to prepare" do
      connection.execute(select, [1], prepare: true)

      assert_instance_of SQLite3::Statement, kept(select)
    end

    it 'runs a kept statement again, with the values bound this time' do
      connection.execute(select, [1], prepare: true)

      assert_equal [[3]], connection.execute(select, [2], prepare: true)
    end

    it 'prepares a statement once, however many times it runs' do
      2.times { |number| connection.execute(select, [number], prepare: true) }

      assert_equal 2, kept(select).stat(:runs)
    end

    it "doesn't keep a statement whose prepare fails" do
      error { connection.execute('SELEC 1', prepare: true) }

      assert_nil kept('SELEC 1')
    end

    describe 'with its cache full' do
      let(:statements) { Skyward::ORM::Adapters::StatementCache.new(1) }

      it 'closes the least recently used statement as it keeps another' do
        connection.execute('SELECT 1', prepare: true)
        evicted = kept('SELECT 1')
        connection.execute('SELECT 2', prepare: true)

        assert_predicate evicted, :closed?
      end
    end

    it 'resets a kept statement once it has run' do
      connection.execute(select, [1], prepare: true)

      refute_predicate kept(select), :done?
    end

    it 'keeps a statement whose run fails' do
      insert = 'INSERT INTO lists (name) VALUES (?)'
      connection.execute(insert, ['Home'], prepare: true)
      error { connection.execute(insert, ['Home'], prepare: true) }

      refute_nil kept(insert)
    end

    it "raises the error a statement it doesn't keep raises" do
      insert = 'INSERT INTO lists (name) VALUES (?)'
      connection.execute(insert, ['Home'])
      unkept = error { connection.execute(insert, ['Home']) }

      assert_equal(unkept, error { connection.execute(insert, ['Home'], prepare: true) })
    end
  end

  describe '#execute2' do
    it "returns the column names, then each row's values" do
      assert_equal [%w[title done], ['Milk', 1]], connection.execute2('SELECT ? AS title, ? AS done', 'Milk', 1)
    end

    it 'names the columns when there are no rows' do
      assert_equal [['name']], connection.execute2('SELECT name FROM lists')
    end

    it "keeps a statement it's asked to prepare, and returns its column names and rows" do
      connection.execute2('SELECT ? AS title', 'Milk', prepare: true)

      assert_equal [['title'], ['Tea']], connection.execute2('SELECT ? AS title', 'Tea', prepare: true)
    end

    it 'names the columns a kept statement returns once a migration has added one' do
      connection.execute("INSERT INTO lists VALUES ('Home')")
      connection.execute2('SELECT * FROM lists', prepare: true)
      connection.execute_batch("ALTER TABLE lists ADD COLUMN slug TEXT DEFAULT 'home'")

      assert_equal [%w[name slug], %w[Home home]], connection.execute2('SELECT * FROM lists', prepare: true)
    end
  end

  describe '#execute_batch' do
    it 'runs every statement in the SQL' do
      connection.execute_batch("INSERT INTO lists VALUES ('Home'); INSERT INTO lists VALUES ('Work');")

      assert_equal [['Home'], ['Work']], connection.execute('SELECT name FROM lists')
    end
  end

  describe '#changes' do
    it 'is how many rows the latest write changed, kept or not' do
      connection.execute("INSERT INTO lists VALUES ('Home'), ('Work')")
      connection.execute('UPDATE lists SET name = name || ?', ['!'], prepare: true)

      assert_equal 2, connection.changes
    end
  end

  describe '#transaction_active?' do
    it 'is false outside a transaction' do
      refute_predicate connection, :transaction_active?
    end

    it 'is true inside one' do
      connection.execute('BEGIN')

      assert_predicate connection, :transaction_active?
    end
  end

  describe '#close' do
    it 'closes every statement it kept' do
      connection.execute(select, [1], prepare: true)
      statement = kept(select)
      connection.close

      assert_predicate statement, :closed?
    end

    it 'closes the database' do
      connection.close

      assert_predicate database, :closed?
    end
  end
end
