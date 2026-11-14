# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Adapters::StatementCache do
  let(:cache) { Skyward::ORM::Adapters::StatementCache.new(2) }

  describe '#keeps?' do
    it 'keeps a statement with 100 binds' do
      assert cache.keeps?(Array.new(100, 1))
    end

    it "doesn't keep one with more" do
      refute cache.keeps?(Array.new(101, 1))
    end
  end

  describe '#fetch' do
    it "is nil for SQL it doesn't keep" do
      assert_nil cache.fetch('SELECT 1')
    end

    it 'returns the statement kept for the SQL' do
      cache.store('SELECT 1', :first)

      assert_equal :first, cache.fetch('SELECT 1')
    end

    it 'makes the statement the most recently used' do
      cache.store('SELECT 1', :first)
      cache.store('SELECT 2', :second)
      cache.fetch('SELECT 1')

      assert_equal :second, cache.store('SELECT 3', :third)
    end
  end

  describe '#store' do
    it 'evicts nothing while it holds no more than its limit' do
      cache.store('SELECT 1', :first)

      assert_nil cache.store('SELECT 2', :second)
    end

    it 'evicts the least recently used once it holds more, and returns it' do
      cache.store('SELECT 1', :first)
      cache.store('SELECT 2', :second)

      assert_equal :first, cache.store('SELECT 3', :third)
    end

    it 'forgets the statement it evicts' do
      cache.store('SELECT 1', :first)
      cache.store('SELECT 2', :second)
      cache.store('SELECT 3', :third)

      assert_nil cache.fetch('SELECT 1')
    end

    it 'holds 1,000 statements by default' do
      cache = Skyward::ORM::Adapters::StatementCache.new
      evicted = (1..1_001).map { |number| cache.store("SELECT #{number}", number) }

      assert_equal [1], evicted.compact
    end
  end

  describe '#clear' do
    it 'returns every statement it kept' do
      cache.store('SELECT 1', :first)
      cache.store('SELECT 2', :second)

      assert_equal %i[first second], cache.clear
    end

    it 'forgets them' do
      cache.store('SELECT 1', :first)
      cache.clear

      assert_nil cache.fetch('SELECT 1')
    end
  end
end
