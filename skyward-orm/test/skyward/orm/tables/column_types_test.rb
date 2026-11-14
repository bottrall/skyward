# frozen_string_literal: true

require 'test_helper'
require_relative '../../../fixtures/tables/tables_fixtures'

describe Skyward::ORM::Tables::ColumnTypes do
  signatures = File.expand_path('../../../fixtures/tables/sig', __dir__)
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(signatures),
    refinements: Skyward::ORM::Tables::ColumnTypes::REFINEMENTS
  )
  column_types = 'A column is Integer, Float, BigDecimal, String, bool, Date, Time, uuid, int32, int16, ' \
                 'a union of symbols, Hash[String, untyped] or Array[T], any of them nullable, or untyped.'
  elements = 'An Array column is Array[T], where T is Integer, Float, BigDecimal, String, bool, Date, Time ' \
             "or a union of symbols, and isn't nullable."
  fixtures = File.expand_path('../../../fixtures/tables/tables_fixtures.rb', __dir__).delete_prefix("#{Dir.pwd}/")
  source = File.readlines(fixtures, chomp: true)

  counting_reader = Class.new do
    attr_reader :reads

    def initialize(reader)
      @reader = reader
      @reads = 0
    end

    def type_name(klass)
      @reads += 1
      @reader.type_name(klass)
    end

    def method_type(type_name, method_name)
      @reads += 1
      @reader.method_type(type_name, method_name)
    end

    def read(type)
      @reads += 1
      @reader.read(type)
    end
  end

  let(:types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }

  def column(name, type, nullable: false, symbols: [], element: nil)
    Skyward::ORM::Tables::Column.new(name:, type:, nullable:, symbols:, element:)
  end

  def refusal(klass)
    assert_raises(Skyward::Core::BootError) { types.columns(klass) }.message
  end

  define_method(:excerpt) do |klass, part|
    start = source.index { |text| text.include?("class #{klass.name.delete_prefix('TablesFixtures::')} <") }.to_i
    line = source.each_index.find { |index| index > start && source.fetch(index).include?('attr_reader') }.to_i
    text = source.fetch(line).strip
    "\n\n    #{fixtures}:#{line + 1}\n    #{text}\n    #{' ' * text.index(part).to_i}#{'^' * part.size}"
  end

  describe '#columns' do
    it "resolves the README's Todo" do
      expected = [
        column(:id, :integer),
        column(:list_id, :integer),
        column(:title, :string),
        column(:priority, :enum, symbols: %i[low normal high]),
        column(:due_on, :date, nullable: true),
        column(:done, :bool),
        column(:created_at, :time)
      ]

      assert_equal expected, types.columns(TablesFixtures::Todo)
    end

    it 'maps every column type' do
      expected = [
        column(:integer, :integer),
        column(:float, :float),
        column(:string, :string),
        column(:bool, :bool),
        column(:date, :date),
        column(:time, :time),
        column(:enum, :enum, symbols: %i[low high]),
        column(:optional, :integer, nullable: true),
        column(:or_nil, :string, nullable: true),
        column(:aliased, :enum, symbols: %i[low normal high]),
        column(:nullable_enum, :enum, nullable: true, symbols: %i[low normal high]),
        column(:decimal, :decimal),
        column(:nullable_decimal, :decimal, nullable: true),
        column(:json, :json),
        column(:nullable_json, :json, nullable: true),
        column(:untyped, :untyped),
        column(:unannotated, :untyped)
      ]

      assert_equal expected, types.columns(TablesFixtures::Typed)
    end

    it "maps each of Skyward ORM's aliases to the column type it names" do
      expected = [
        column(:id, :uuid),
        column(:logins, :int32),
        column(:rank, :int16),
        column(:invited_by, :uuid, nullable: true)
      ]

      assert_equal expected, types.columns(TablesFixtures::Refined)
    end

    it "maps an Array of each element type, keeping a symbol union's symbols, and a nullable one" do
      expected = [
        column(:id, :integer),
        *%i[integer float decimal string bool date time].map { |element| column(:"#{element}s", :array, element:) },
        column(:weekdays, :array, element: :enum, symbols: %i[mon tue wed thu fri]),
        column(:tags, :array, nullable: true, element: :string)
      ]

      assert_equal expected, types.columns(TablesFixtures::Arrayed)
    end

    it "resolves a row class's members, untyped where its signature has no reader" do
      expected = [column(:title, :string), column(:due_on, :date), column(:note, :untyped)]

      assert_equal expected, types.columns(TablesFixtures::Due)
    end

    it 'leaves every column of a class with no signature untyped' do
      assert_equal [column(:id, :untyped)], types.columns(TablesFixtures::Unsigned)
    end

    it "reads a class's types once" do
      counting = counting_reader.new(reader)
      cached = Skyward::ORM::Tables::ColumnTypes.new(counting)
      cached.columns(TablesFixtures::Todo)
      reads = counting.reads
      cached.columns(TablesFixtures::Todo)

      assert_equal reads, counting.reads
    end

    it "refuses a type core can't read, with its explanation" do
      assert_equal "TablesFixtures::Tuple#tags can't be read: Skyward ORM doesn't read [ String, Integer ]. " \
                   "#{column_types}#{excerpt(TablesFixtures::Tuple, ':tags')}",
                   refusal(TablesFixtures::Tuple)
    end

    it "says where core found a type it can't read" do
      assert_equal "TablesFixtures::Holder#pair can't be read: Skyward ORM doesn't read [ String, Integer ], " \
                   "at TablesFixtures::Pair#both. #{column_types}#{excerpt(TablesFixtures::Holder, ':pair')}",
                   refusal(TablesFixtures::Holder)
    end

    it "names the column when core can't read its type at all" do
      assert_equal 'TablesFixtures::Nested#node is TablesFixtures::Node. ' \
                   "Can't read TablesFixtures::Node: it refers to itself through " \
                   "TablesFixtures::Node -> TablesFixtures::Node#{excerpt(TablesFixtures::Nested, ':node')}",
                   refusal(TablesFixtures::Nested)
    end

    it 'refuses a record as not a column type yet' do
      assert_equal "TablesFixtures::Recorded#point is { x: Integer, y: Integer }, which isn't a column type yet. " \
                   "#{column_types}#{excerpt(TablesFixtures::Recorded, ':point')}",
                   refusal(TablesFixtures::Recorded)
    end

    it 'refuses a class as not a column type yet' do
      assert_equal "TablesFixtures::Classed#list is TablesFixtures::List, which isn't a column type yet. " \
                   "#{column_types}#{excerpt(TablesFixtures::Classed, ':list')}",
                   refusal(TablesFixtures::Classed)
    end

    {
      'an Array of a nullable type' => [TablesFixtures::Listed, :tags, 'Array[String?]'],
      'an Array of Arrays' => [TablesFixtures::Grid, :rows, 'Array[Array[Integer]]'],
      'an Array of untyped' => [TablesFixtures::Loose, :items, 'Array[untyped]'],
      'an Array of a Hash' => [TablesFixtures::Documented, :documents, 'Array[Hash[String, untyped]]'],
      'an Array of a record' => [TablesFixtures::Plotted, :coordinates, 'Array[{ x: Integer, y: Integer }]'],
      'an Array of a class' => [TablesFixtures::Grouped, :lists, 'Array[TablesFixtures::List]']
    }.each do |refused, (klass, name, written)|
      it "refuses #{refused}, saying what an element can be" do
        assert_equal "#{klass}##{name} is #{written}, which isn't a column type. #{elements}" \
                     "#{excerpt(klass, ":#{name}")}",
                     refusal(klass)
      end
    end

    it "refuses an Array of one of Skyward ORM's aliases as not a column type yet" do
      assert_equal "TablesFixtures::Identified#ids is Array[Skyward::ORM::uuid], which isn't a column type yet. " \
                   "#{elements}#{excerpt(TablesFixtures::Identified, ':ids')}",
                   refusal(TablesFixtures::Identified)
    end

    it 'refuses a hash of anything but untyped, pointing at Hash[String, untyped]' do
      assert_equal "TablesFixtures::Hashed#settings is Hash[String, String], which isn't a column type. " \
                   'A Hash column is Hash[String, untyped], holding any JSON.' \
                   "#{excerpt(TablesFixtures::Hashed, ':settings')}",
                   refusal(TablesFixtures::Hashed)
    end

    it 'refuses a union of other types' do
      assert_equal "TablesFixtures::Mixed#value is String | Integer, which isn't a column type. #{column_types}" \
                   "#{excerpt(TablesFixtures::Mixed, ':value')}",
                   refusal(TablesFixtures::Mixed)
    end

    it 'refuses a literal' do
      assert_equal "TablesFixtures::Literal#kind is \"todo\", which isn't a column type. #{column_types}" \
                   "#{excerpt(TablesFixtures::Literal, ':kind')}",
                   refusal(TablesFixtures::Literal)
    end

    it 'suggests the class core suggests for a misspelt one' do
      assert_equal "TablesFixtures::Misnamed#memo can't be read: Skyward ORM doesn't read Strng, " \
                   "at TablesFixtures::Memo#body. #{column_types}#{excerpt(TablesFixtures::Misnamed, 'Memo')}\n" \
                   'Did you mean String?',
                   refusal(TablesFixtures::Misnamed)
    end
  end
end
