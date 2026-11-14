# frozen_string_literal: true

require 'test_helper'
require_relative '../../../fixtures/tables/tables_fixtures'

describe Skyward::ORM::Tables::Sources do
  sources = Skyward::ORM::Tables::Sources
  path = File.expand_path('../../../fixtures/tables/tables_fixtures.rb', __dir__)
  source = File.readlines(path, chomp: true)

  define_method(:under) do |snippet, part|
    line = source.index { |text| text.include?(snippet) }.to_i + 1
    text = source.fetch(line - 1)
    start = text.index(part).to_i
    Skyward::Core::Diagnostics::Spot.new(path:, line:, text:, columns: start...(start + part.size))
  end

  describe '.declaration' do
    it 'is under the column a declaration names' do
      assert_equal under('index :lsit_id', ':due_on'), sources.declaration(TablesFixtures::Misspelt, :index, :due_on)
    end

    it "is under a default's key" do
      assert_equal under('default dnoe:', 'dnoe:'), sources.declaration(TablesFixtures::Misspelt, :default, :dnoe)
    end

    it 'is nil for a column no declaration names' do
      assert_nil sources.declaration(TablesFixtures::Literal, :primary_key, :id)
    end
  end

  describe '.reader' do
    it "is under the type in the reader's #: comment" do
      assert_equal under('attr_reader :tags #:', 'Array[String]'), sources.reader(TablesFixtures::Annotated, :tags)
    end

    it "is under the column's name when its type is in a hand-written signature" do
      assert_equal under('attr_reader :point', ':point'), sources.reader(TablesFixtures::Recorded, :point)
    end

    it "is nil for a class that isn't a table class" do
      assert_nil sources.reader(TablesFixtures::Due, :title)
    end

    it 'is nil for a column no attr_reader declares' do
      assert_nil sources.reader(Class.new(Skyward::ORM::Record) { attr_reader :id }, :id)
    end
  end

  describe '.class_name' do
    it "is under the name in the class's class line" do
      assert_equal under('class Typed <', 'Typed'), sources.class_name(TablesFixtures::Typed)
    end

    it 'is nil for an anonymous class' do
      assert_nil sources.class_name(Class.new)
    end

    it 'is nil for a class from Class.new that a constant names' do
      assert_nil sources.class_name(TablesFixtures::Pair)
    end

    it 'is nil for a class in an anonymous module' do
      namespace = Module.new
      namespace.const_set(:Inner, Class.new)

      assert_nil sources.class_name(namespace.const_get(:Inner))
    end

    it "is nil for a class from eval'd code, which has no file" do
      namespace = Module.new
      Object.const_set(:SourcesEvaled, namespace)
      namespace.module_eval('class Inner; end') # rubocop:disable Style/EvalWithLocation -- code with no file is what's tested

      assert_nil sources.class_name(namespace.const_get(:Inner))
    ensure
      Object.send(:remove_const, :SourcesEvaled)
    end
  end

  describe '.explain' do
    spot = Skyward::Core::Diagnostics::Spot.new(path: 'app/todo.rb', line: 7, text: 'index :lsit_id', columns: 6...14)

    it 'is the message alone with no spot or suggestion' do
      assert_equal 'Todo has no table.', sources.explain('Todo has no table.', [nil])
    end

    it 'adds the excerpt of the spots, then the suggestion' do
      expected = <<~MESSAGE.chomp
        Todo has no column lsit_id.

            app/todo.rb:7
            index :lsit_id
                  ^^^^^^^^
        Did you mean list_id?
      MESSAGE

      assert_equal expected, sources.explain('Todo has no column lsit_id.', [spot], 'list_id')
    end

    it 'adds a suggestion with no excerpt on the next line' do
      assert_equal "Todo has no column lsit_id.\nDid you mean list_id?",
                   sources.explain('Todo has no column lsit_id.', [], 'list_id')
    end
  end

  describe '.join' do
    it 'puts each one-line problem on its own line' do
      assert_equal "one\ntwo", sources.join(%w[one two])
    end

    it 'puts a blank line between problems when any has more than one line' do
      assert_equal "one\n\ntwo\nDid you mean too?", sources.join(['one', "two\nDid you mean too?"])
    end
  end
end
