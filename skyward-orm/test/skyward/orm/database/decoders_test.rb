# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Database::Decoders do
  decoders = Skyward::ORM::Database::Decoders

  # Decodes a value as its column's type beside it, so a row shows which
  # column decoded each value.
  tagging = Module.new do
    extend self

    def decoding(column, value) = "[#{column.type.inspect}, #{value}]"
  end

  define_method(:column) do |name, type|
    Skyward::ORM::Tables::Column.new(name:, type:, nullable: true, symbols: [], element: nil)
  end

  define_method(:decode) do |row, values, positions: [0, 1]|
    decoders.compile(row, [column(:id, :integer), column(:title, :string)], positions, tagging).call(values)
  end

  let(:todo) { Data.define(:id, :title) }

  describe '.compile' do
    it 'decodes each value by its column' do
      assert_equal todo.new(id: [:integer, 1], title: [:string, 'Milk']), decode(todo, [1, 'Milk'])
    end

    it "reads each value at its member's position" do
      assert_equal todo.new(id: [:integer, 1], title: [:string, 'Milk']), decode(todo, ['Milk', 1], positions: [1, 0])
    end

    it 'keeps nil as nil, without decoding it' do
      assert_equal todo.new(id: nil, title: nil), decode(todo, [nil, nil])
    end

    it "loads a table class's row, without new" do
      table = Class.new(Skyward::ORM::Record) do
        attr_reader :id, :title

        def self.new(**) = raise(NotImplementedError, "a decoder loads a table class's row")
      end

      assert_equal({ id: [:integer, 1], title: [:string, 'Milk'] }, decode(table, [1, 'Milk']).to_h)
    end

    it 'builds a table class that defines its own initialize with new, so its initialize runs' do
      table = Class.new(Skyward::ORM::Record) do
        attr_reader :id, :title

        def initialize(**columns)
          super(**columns, title: 'Initialized')
        end
      end

      assert_equal 'Initialized', decode(table, [1, 'Milk']).title
    end

    it "builds a class by its members' keywords" do
      keyworded = Struct.new(:id, :title, keyword_init: true)

      assert_equal keyworded.new(id: [:integer, 1], title: [:string, 'Milk']), decode(keyworded, [1, 'Milk'])
    end

    it 'names a member called after a Ruby keyword' do
      reserved = Data.define(:end)

      assert_equal reserved.new(end: [:integer, 2]),
                   decoders.compile(reserved, [column(:end, :integer)], [0], tagging).call([2])
    end
  end
end
