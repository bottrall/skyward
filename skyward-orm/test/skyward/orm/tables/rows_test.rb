# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Tables::Rows do
  rows = Skyward::ORM::Tables::Rows

  define_method(:table) do |*columns|
    Class.new do
      class_eval(rows.source(columns), __FILE__, __LINE__)
      attr_reader(*columns)
    end
  end

  def row(table, **columns)
    built = table.allocate
    built.send(:initialize_columns, columns)
    built
  end

  def loaded(table, *values) = table.allocate.send(:load_columns, *values)

  let(:todo) { table(:id, :title) }

  describe '.source' do
    it 'sets each column' do
      assert_equal([1, 'Buy milk'], row(todo, id: 1, title: 'Buy milk').then { |built| [built.id, built.title] })
    end

    it 'sets a column named after a Ruby keyword' do
      assert_equal 2, row(table(:end), end: 2).end
    end

    it 'raises naming the columns left out' do
      error = assert_raises(ArgumentError) { row(todo, id: 1) }

      assert_equal "#{todo} is missing title", error.message
    end

    it "raises naming the columns it doesn't have" do
      error = assert_raises(ArgumentError) { row(todo, id: 1, title: 'Buy milk', done: false) }

      assert_equal "#{todo} has no column done", error.message
    end

    it "keeps a row's columns private to it" do
      assert_raises(NoMethodError) { todo.allocate.initialize_columns({ id: 1, title: 'Buy milk' }) }
    end

    it 'loads each column from its value, in order' do
      assert_equal row(todo, id: 1, title: 'Buy milk'), loaded(todo, 1, 'Buy milk')
    end

    it 'loads a column named after a Ruby keyword' do
      assert_equal 2, loaded(table(:end), 2).end
    end

    it 'freezes a row it loads' do
      assert_predicate loaded(todo, 1, 'Buy milk'), :frozen?
    end

    it 'keeps loading a row private to it' do
      assert_raises(NoMethodError) { todo.allocate.load_columns(1, 'Buy milk') }
    end

    it 'loads a row with no columns' do
      assert_empty loaded(table).to_h
    end

    it 'makes a hash of the columns' do
      assert_equal({ id: 1, title: 'Buy milk' }, row(todo, id: 1, title: 'Buy milk').to_h)
    end

    it 'deconstructs every column for a pattern that asks for any key' do
      assert_equal({ id: 1, title: 'Buy milk' }, row(todo, id: 1, title: 'Buy milk').deconstruct_keys(nil))
    end

    it 'deconstructs only the columns a pattern asks for' do
      assert_equal({ title: 'Buy milk' }, row(todo, id: 1, title: 'Buy milk').deconstruct_keys([:title]))
    end

    it "leaves out a key that isn't a column" do
      assert_equal({ id: 1 }, row(todo, id: 1, title: 'Buy milk').deconstruct_keys(%i[id done]))
    end

    it 'matches a pattern' do
      matched =
        case row(todo, id: 1, title: 'Buy milk')
        in { title: 'Buy milk' } then true
        else false
        end

      assert matched
    end

    it 'deconstructs a row with no columns' do
      assert_empty row(table).deconstruct_keys([:id])
    end

    it 'shows the class and each column' do
      milk = row(todo, id: 1, title: 'Buy milk')

      assert_equal "#<#{milk.class} id=1, title=\"Buy milk\">", milk.inspect
    end

    it 'shows a row with no columns' do
      empty = table

      assert_equal "#<#{empty} >", row(empty).inspect
    end

    it 'makes rows with equal columns ==' do
      assert_equal row(todo, id: 1, title: 'Buy milk'), row(todo, id: 1.0, title: 'Buy milk')
    end

    it 'tells rows with a different column apart' do
      refute_equal row(todo, id: 1, title: 'Buy milk'), row(todo, id: 1, title: 'Buy eggs')
    end

    it 'tells rows of different tables apart' do
      refute_equal row(table(:id, :title), id: 1, title: 'Buy milk'), row(todo, id: 1, title: 'Buy milk')
    end

    it 'makes rows with eql? columns eql?' do
      assert row(todo, id: 1, title: 'Buy milk').eql?(row(todo, id: 1, title: 'Buy milk'))
    end

    it 'tells rows apart by eql?, as Hash keys do' do
      refute row(todo, id: 1, title: 'Buy milk').eql?(row(todo, id: 1.0, title: 'Buy milk'))
    end

    it 'tells rows of different tables apart by eql?' do
      refute row(table(:id, :title), id: 1, title: 'Buy milk').eql?(row(todo, id: 1, title: 'Buy milk'))
    end

    it 'hashes equal rows the same' do
      assert_equal row(todo, id: 1, title: 'Buy milk').hash, row(todo, id: 1, title: 'Buy milk').hash
    end

    it 'hashes rows of different tables differently' do
      refute_equal row(table(:id, :title), id: 1, title: 'Buy milk').hash, row(todo, id: 1, title: 'Buy milk').hash
    end

    it 'builds a row with no columns' do
      assert_empty row(table).to_h
    end
  end

  describe '.mismatch' do
    it "names both the columns left out and the ones it doesn't have" do
      assert_equal "#{todo} is missing title, done, and has no column colour, size",
                   rows.mismatch(todo, %i[id title done], %i[id colour size])
    end
  end
end
