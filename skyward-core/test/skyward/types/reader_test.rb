# frozen_string_literal: true

require "test_helper"
require_relative "../../fixtures/types/reader_fixtures"

describe Skyward::Types::Reader do
  types = Skyward::Types
  builder = Skyward::Signatures::Loader.new.load(File.expand_path("../../fixtures/types", __dir__))
  reader = Skyward::Types::Reader.new(builder)

  integer = types::Scalar.new(name: :integer)
  string = types::Scalar.new(name: :string)
  priority = types::Enum.new(symbols: %i[low normal high])
  record_hint = "a record, or a class with public typed attr_readers"

  define_method(:read) { |source| reader.read(RBS::Parser.parse_type(source)) }

  describe "#read" do
    it "reads bool" do
      assert_equal types::Scalar.new(name: :bool), read("bool")
    end

    it "reads untyped" do
      assert_equal types::Scalar.new(name: :untyped), read("untyped")
    end

    it "reads nil as a literal" do
      assert_equal types::Literal.new(value: nil), read("nil")
    end

    it "reads a symbol literal as an enum of one" do
      assert_equal types::Enum.new(symbols: [:low]), read(":low")
    end

    it "reads String, Integer and boolean literals" do
      assert_equal(
        [types::Literal.new(value: "ok"), types::Literal.new(value: 1), types::Literal.new(value: true)],
        ['"ok"', "1", "true"].map { |source| read(source) }
      )
    end

    it "reads T? as nullable" do
      assert_equal types::Nullable.new(type: types::Scalar.new(name: :date)), read("::Date?")
    end

    it "reads T?? as nullable once" do
      assert_equal types::Nullable.new(type: integer), read("::Integer??")
    end

    it "reads nil? as nil" do
      assert_equal types::Literal.new(value: nil), read("nil?")
    end

    it "reads T? of an unreadable type as unreadable" do
      assert_instance_of types::Unreadable, read("[::Integer]?")
    end

    it "reads a union of one type, repeated, as that type" do
      assert_equal integer, read("::Integer | ::Integer")
    end

    it "reads T | nil as nullable" do
      assert_equal types::Nullable.new(type: integer), read("::Integer | nil")
    end

    it "reads a union of symbol literals as one enum" do
      assert_equal priority, read(":low | :normal | :high")
    end

    it "merges symbols from aliases into one enum, without duplicates" do
      assert_equal types::Enum.new(symbols: %i[low normal high urgent]),
                   read("::ReaderFixtures::priority | :low | :urgent")
    end

    it "reads a union of other types as a union, in written order" do
      assert_equal types::Union.new(types: [string, integer]), read("::String | ::Integer")
    end

    it "flattens nested unions and drops duplicates" do
      float = types::Scalar.new(name: :float)

      assert_equal types::Union.new(types: [integer, float, string]),
                   read("::ReaderFixtures::number | ::String | ::Integer")
    end

    it "lifts a nullable member to the whole union" do
      assert_equal types::Nullable.new(type: types::Union.new(types: [integer, string])), read("::Integer? | ::String")
    end

    it "reads a union with an unreadable member as unreadable" do
      assert_instance_of types::Unreadable, read("::Integer | [::Integer, ::String]")
    end

    it "expands a type alias" do
      assert_equal priority, read("::ReaderFixtures::priority")
    end

    it "expands a generic type alias" do
      assert_equal types::ArrayOf.new(type: string), read("::ReaderFixtures::list[::String]")
    end

    it "expands a generic type alias applied to itself without calling it recursive" do
      assert_equal types::ArrayOf.new(type: types::ArrayOf.new(type: string)),
                   read("::ReaderFixtures::list[::ReaderFixtures::list[::String]]")
    end

    it "raises BootError for an alias that refers to itself" do
      error = assert_raises(Skyward::BootError) { read("::ReaderFixtures::tree") }

      assert_equal "Can't read ReaderFixtures::tree: it refers to itself through " \
                   "ReaderFixtures::tree -> ReaderFixtures::tree",
                   error.message
    end

    it "reads a record's fields in written order" do
      fields = [
        types::Field.new(name: :page, type: integer, required: false),
        types::Field.new(name: :id, type: integer, required: true)
      ]

      assert_equal types::Record.new(fields:), read("{ ?page: ::Integer, id: ::Integer }")
    end

    it "reads a record with an unreadable field as unreadable, found in no class" do
      assert_nil read("{ id: [::Integer] }").at
    end

    it "reads Integer, Float, String, Date and Time as scalars" do
      assert_equal(
        %i[integer float string date time],
        %w[::Integer ::Float ::String ::Date ::Time].map { |source| read(source).name }
      )
    end

    it "reads a bare Array as unreadable, suggesting Array[T]" do
      assert_equal types::Unreadable.new(type: "Array", at: nil, instead: "Array[T]"), read("::Array")
    end

    it "reads Array[T]" do
      assert_equal types::ArrayOf.new(type: integer), read("::Array[::Integer]")
    end

    it "reads Array of an unreadable type as unreadable" do
      assert_instance_of types::Unreadable, read("::Array[[::Integer]]")
    end

    it "reads a class RBS doesn't declare as unreadable" do
      assert_equal types::Unreadable.new(type: "Nowhere", at: nil, instead: record_hint), read("::Nowhere")
    end

    it "reads a module as unreadable" do
      assert_instance_of types::Unreadable, read("::ReaderFixtures::Mixin")
    end

    it "reads a class with no readers as unreadable" do
      assert_equal types::Unreadable.new(type: "ReaderFixtures::Plain", at: nil, instead: record_hint),
                   read("::ReaderFixtures::Plain")
    end

    it "reads a class with only private readers as unreadable" do
      assert_instance_of types::Unreadable, read("::ReaderFixtures::Hidden")
    end

    it "raises BootError for a class with no Ruby class loaded" do
      error = assert_raises(Skyward::BootError) { read("::ReaderFixtures::Orphan") }

      assert_equal "ReaderFixtures::Orphan has an RBS signature, but no Ruby class is loaded with that name",
                   error.message
    end

    it "raises BootError for a class whose Ruby constant isn't a class" do
      assert_raises(Skyward::BootError) { read("::ReaderFixtures::NotAClass") }
    end

    it "raises BootError for a class that refers to itself" do
      error = assert_raises(Skyward::BootError) { read("::ReaderFixtures::Node") }

      assert_equal "Can't read ReaderFixtures::Node: it refers to itself through " \
                   "ReaderFixtures::Node -> ReaderFixtures::Node",
                   error.message
    end

    it "raises BootError for a class that refers to itself through another" do
      error = assert_raises(Skyward::BootError) { read("::ReaderFixtures::Parent") }

      assert_equal "Can't read ReaderFixtures::Parent: it refers to itself through " \
                   "ReaderFixtures::Parent -> ReaderFixtures::Child -> ReaderFixtures::Parent",
                   error.message
    end

    describe "a class with typed readers" do
      todo = reader.read(RBS::Parser.parse_type("::ReaderFixtures::Todo"))

      it "is named in full" do
        assert_equal "ReaderFixtures::Todo", todo.name
      end

      it "finds the Ruby class" do
        assert_equal ReaderFixtures::Todo, todo.klass
      end

      it "takes public instance readers, in written order, across every file, skipping private sections" do
        assert_equal %i[id title priority due_on], todo.fields.map(&:name)
      end

      it "reads each reader's type into a required field" do
        assert_equal types::Field.new(name: :priority, type: priority, required: true), todo.fields.fetch(2)
      end
    end

    it "reads rbs-inline's Data.define the same way" do
      expected = types::Named.new(
        name: "ReaderFixtures::NewTodo",
        klass: ReaderFixtures::NewTodo,
        fields: [
          types::Field.new(name: :title, type: string, required: true),
          types::Field.new(name: :priority, type: priority, required: true)
        ]
      )

      assert_equal expected, read("::ReaderFixtures::NewTodo")
    end

    it "reads a class twice in one type without calling it recursive" do
      assert_equal %i[first second], read("::ReaderFixtures::Pair").fields.map(&:name)
    end

    it "keeps the innermost class and reader" do
      assert_equal "ReaderFixtures::Holder#tags", read("::ReaderFixtures::Outer").at
    end

    it "names the class and reader where an unreadable type was found" do
      expected = types::Unreadable.new(
        type: "Hash[Symbol, untyped]",
        at: "ReaderFixtures::Holder#tags",
        instead: record_hint
      )

      assert_equal expected, read("::ReaderFixtures::Holder")
    end

    it "reads a tuple as unreadable, suggesting an array or a record" do
      assert_equal types::Unreadable.new(type: "[ Integer, String ]", at: nil, instead: "Array[T], or a record"),
                   read("[::Integer, ::String]")
    end

    it "reads an interface as unreadable" do
      assert_equal types::Unreadable.new(type: "ReaderFixtures::_Named", at: nil, instead: record_hint),
                   read("::ReaderFixtures::_Named")
    end

    it "reads a proc as unreadable" do
      assert_equal "^(Integer) -> void", read("^(::Integer) -> void").type
    end

    it "writes an unreadable type without leading colons" do
      assert_equal "Hash[String, Integer]", read("::Hash[::String, ::Integer]").type
    end
  end

  describe "#type_name" do
    it "is nil for an anonymous class" do
      assert_nil reader.type_name(Class.new)
    end

    it "finds the declaration of a class RBS knows" do
      assert_equal RBS::TypeName.parse("::ReaderFixtures::API"), reader.type_name(ReaderFixtures::API)
    end

    it "is nil for a class RBS doesn't know" do
      assert_nil reader.type_name(Class.new { def self.name = "Nowhere" })
    end
  end

  describe "#method_type" do
    it "finds a method's signature" do
      assert_equal "(id: ::Integer) -> ::ReaderFixtures::Todo",
                   reader.method_type(RBS::TypeName.parse("::ReaderFixtures::API"), :show).to_s
    end

    it "is nil for a method RBS doesn't declare" do
      assert_nil reader.method_type(RBS::TypeName.parse("::ReaderFixtures::API"), :destroy)
    end

    it "raises BootError when RBS can't build the class" do
      error = assert_raises(Skyward::BootError) do
        reader.method_type(RBS::TypeName.parse("::ReaderFixtures::Mismatched"), :to_s)
      end

      assert_match(/\ACan't read the RBS signatures: .*Superclass mismatch/, error.message)
    end
  end
end
