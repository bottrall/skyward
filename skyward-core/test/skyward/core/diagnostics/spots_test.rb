# frozen_string_literal: true

require 'test_helper'
require_relative '../../../fixtures/diagnostics/source'

describe Skyward::Core::Diagnostics::Spots do
  spots = Skyward::Core::Diagnostics::Spots
  path = File.expand_path('../../../fixtures/diagnostics/source.rb', __dir__)
  source = File.readlines(path, chomp: true)
  missing = File.expand_path('../../../fixtures/diagnostics/missing.rb', __dir__)

  define_method(:line_of) { |snippet| source.index { |text| text.include?(snippet) }.to_i + 1 }

  define_method(:under) do |snippet, part = snippet|
    line = line_of(snippet)
    text = source.fetch(line - 1)
    start = text.index(part).to_i
    Skyward::Core::Diagnostics::Spot.new(path:, line:, text:, columns: start...(start + part.size))
  end

  describe '.rbs' do
    buffer = RBS::Buffer.new(name: Pathname('sig/box.rbs'), content: "class Box\n  def size: () -> Integer\nend\n")
    _, _, decls = RBS::Parser.parse_signature(buffer)
    box = decls.fetch(0)

    it "is under the location's columns, on its first line" do
      expected = Skyward::Core::Diagnostics::Spot.new(path: 'sig/box.rbs', line: 1, text: 'class Box', columns: 6...9)

      assert_equal expected, spots.rbs(box.location[:name])
    end

    it 'is under the rest of the first line of a location that spans several' do
      assert_equal 0...9, spots.rbs(box.location).columns
    end

    it 'puts one caret under an empty location' do
      assert_equal 2...3, spots.rbs(RBS::Location.new(buffer, 2, 2)).columns
    end
  end

  describe '.keyword_parameter' do
    show = DiagnosticsFixtures.instance_method(:show)

    it 'is under a required keyword parameter' do
      assert_equal under('def show', 'todo_id:'), spots.keyword_parameter(show, :todo_id)
    end

    it 'is under an optional keyword parameter and its default' do
      assert_equal under('def show', 'limit: 10'), spots.keyword_parameter(show, :limit)
    end

    it "is nil for a keyword the method doesn't have" do
      assert_nil spots.keyword_parameter(show, :id)
    end

    it 'is nil for a method with no parameters' do
      assert_nil spots.keyword_parameter(DiagnosticsFixtures.instance_method(:index), :id)
    end
  end

  describe '.parameters' do
    it 'is under the whole parameter list' do
      assert_equal under('def show', 'todo_id:, limit: 10'),
                   spots.parameters(DiagnosticsFixtures.instance_method(:show))
    end

    it 'is under the rest of the first line of a parameter list that spans several' do
      assert_equal under('title:,'), spots.parameters(DiagnosticsFixtures.instance_method(:create))
    end

    it 'is nil for a method with no parameters' do
      assert_nil spots.parameters(DiagnosticsFixtures.instance_method(:index))
    end
  end

  describe '.method_name' do
    it "is under the method's name" do
      assert_equal under('def show', 'show'), spots.method_name(DiagnosticsFixtures.instance_method(:show))
    end

    it 'is under the name of a bound method, found by its original name' do
      aliased = Class.new(DiagnosticsFixtures) { alias_method :display, :show }

      assert_equal under('def show', 'show'), spots.method_name(aliased.new.method(:display))
    end

    it 'is nil for a method with no source location' do
      assert_nil spots.method_name(1.method(:+))
    end

    it "is nil for a method whose file isn't on disk" do
      # A variable, so RuboCop's Style/EvalWithLocation leaves the missing path alone.
      code = 'def gone = nil'
      klass = Class.new { class_eval(code, missing, 1) }

      assert_nil spots.method_name(klass.instance_method(:gone))
    end

    it "is nil when the method's line no longer defines it" do
      klass = Class.new { class_eval('def moved = nil', __FILE__, __LINE__) }

      assert_nil spots.method_name(klass.instance_method(:moved))
    end
  end

  describe '.keyword_key' do
    it "is under a keyword argument's key" do
      assert_equal under('default lsit_id:', 'lsit_id:'),
                   spots.keyword_key(path, line_of('default lsit_id:'), call: :default, key: :lsit_id)
    end

    it "is nil for a key the call doesn't pass" do
      assert_nil spots.keyword_key(path, line_of('default lsit_id:'), call: :default, key: :list_id)
    end

    it 'is nil for a call with no arguments' do
      assert_nil spots.keyword_key(path, line_of('clear'), call: :clear, key: :lsit_id)
    end

    it 'is nil for a call with no keyword arguments' do
      assert_nil spots.keyword_key(path, line_of('index :lsit_id'), call: :index, key: :lsit_id)
    end

    it 'is nil when no call of that name starts on the line' do
      assert_nil spots.keyword_key(path, line_of('default lsit_id:'), call: :get, key: :lsit_id)
    end

    it "is nil for a file that isn't on disk" do
      assert_nil spots.keyword_key(missing, 1, call: :default, key: :lsit_id)
    end
  end

  describe '.keyword_value' do
    it "is under a keyword argument's value" do
      assert_equal under("get '/:id'", ':show'), spots.keyword_value(path, line_of("get '/:id'"), call: :get, key: :to)
    end

    it 'counts characters, not bytes, after non-ASCII text' do
      assert_equal under('café', ':show'), spots.keyword_value(path, line_of('café'), call: :get, key: :to)
    end
  end

  describe '.symbol' do
    it 'is under a Symbol argument with the value' do
      assert_equal under('index :lsit_id', ':lsit_id'),
                   spots.symbol(path, line_of('index :lsit_id'), call: :index, value: :lsit_id)
    end

    it 'is nil when no Symbol argument has the value' do
      assert_nil spots.symbol(path, line_of('index :lsit_id'), call: :index, value: :list_id)
    end
  end

  describe '.string' do
    it 'is under a part of a String argument' do
      assert_equal under("get '/:id'", ':id'), spots.string(path, line_of("get '/:id'"), call: :get, part: ':id')
    end

    it 'counts characters, not bytes, after non-ASCII text' do
      assert_equal under('café', ':id'), spots.string(path, line_of('café'), call: :get, part: ':id')
    end

    it 'is nil when no String argument has the part' do
      assert_nil spots.string(path, line_of("get '/:id'"), call: :get, part: ':todo_id')
    end
  end

  describe '.reader_type' do
    it "is under the type in an attr_reader's #: comment" do
      assert_equal under('attr_reader :list', 'Lisst'), spots.reader_type(path, line_of('attr_reader :list'))
    end

    it 'is nil for an attr_reader with no #: comment' do
      assert_nil spots.reader_type(path, line_of('attr_reader :count'))
    end

    it 'is nil for a line with no attr_reader' do
      assert_nil spots.reader_type(path, line_of('def show'))
    end

    it "is nil for a file that isn't on disk" do
      assert_nil spots.reader_type(missing, 1)
    end
  end
end
