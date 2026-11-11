# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Tables::ColumnTypes do
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(
    Skyward::Core::Signatures.load(signatures),
    refinements: Skyward::ORM::Tables::ColumnTypes::REFINEMENTS
  )
  column_types = "A column is Integer, Float, String, bool, Date, Time, uuid, int32, int16 or a union of symbols, " \
                 "any of them nullable, or untyped."

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

  def column(name, type, nullable: false, symbols: [])
    Skyward::ORM::Tables::Column.new(name:, type:, nullable:, symbols:)
  end

  def refusal(klass)
    assert_raises(Skyward::Core::BootError) { types.columns(klass) }.message
  end

  describe "#columns" do
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

    it "maps every column type" do
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

    it "resolves a row class's members, untyped where its signature has no reader" do
      expected = [column(:title, :string), column(:due_on, :date), column(:note, :untyped)]

      assert_equal expected, types.columns(TablesFixtures::Due)
    end

    it "leaves every column of a class with no signature untyped" do
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
                   "#{column_types}",
                   refusal(TablesFixtures::Tuple)
    end

    it "says where core found a type it can't read" do
      assert_equal "TablesFixtures::Holder#pair can't be read: Skyward ORM doesn't read [ String, Integer ], " \
                   "at TablesFixtures::Pair#both. #{column_types}",
                   refusal(TablesFixtures::Holder)
    end

    it "names the column when core can't read its type at all" do
      assert_equal "TablesFixtures::Nested#node is TablesFixtures::Node. " \
                   "Can't read TablesFixtures::Node: it refers to itself through " \
                   "TablesFixtures::Node -> TablesFixtures::Node",
                   refusal(TablesFixtures::Nested)
    end

    it "refuses a BigDecimal as not a column type yet" do
      assert_equal "TablesFixtures::Decimal#price is BigDecimal?, which isn't a column type yet. #{column_types}",
                   refusal(TablesFixtures::Decimal)
    end

    it "refuses a record as not a column type yet" do
      assert_equal "TablesFixtures::Recorded#point is { x: Integer, y: Integer }, which isn't a column type yet. " \
                   "#{column_types}",
                   refusal(TablesFixtures::Recorded)
    end

    it "refuses a class as not a column type yet" do
      assert_equal "TablesFixtures::Classed#list is TablesFixtures::List, which isn't a column type yet. " \
                   "#{column_types}",
                   refusal(TablesFixtures::Classed)
    end

    it "refuses an array as not a column type yet" do
      assert_equal "TablesFixtures::Listed#tags is Array[String]?, which isn't a column type yet. #{column_types}",
                   refusal(TablesFixtures::Listed)
    end

    it "refuses a hash as not a column type yet" do
      assert_equal "TablesFixtures::Hashed#settings is Hash[String, String], which isn't a column type yet. " \
                   "#{column_types}",
                   refusal(TablesFixtures::Hashed)
    end

    it "refuses a union of other types" do
      assert_equal "TablesFixtures::Mixed#value is String | Integer, which isn't a column type. #{column_types}",
                   refusal(TablesFixtures::Mixed)
    end

    it "refuses a literal" do
      assert_equal "TablesFixtures::Literal#kind is \"todo\", which isn't a column type. #{column_types}",
                   refusal(TablesFixtures::Literal)
    end
  end
end
