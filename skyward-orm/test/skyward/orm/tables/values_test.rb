# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Tables::Values do
  todo = TablesFixtures::Todo

  def column(type, nullable: false, symbols: [])
    Skyward::ORM::Tables::Column.new(name: :value, type:, nullable:, symbols:)
  end

  def mismatch(column, value) = Skyward::ORM::Tables::Values.mismatch(TablesFixtures::Todo, column, value)

  describe ".mismatch" do
    describe "on a JSON column" do
      it "takes nil for a nullable one" do
        assert_nil mismatch(column(:json, nullable: true), nil)
      end

      it "refuses nil for one that isn't nullable" do
        assert_equal "#{todo}.value is Hash[String, untyped], not nil (NilClass)", mismatch(column(:json), nil)
      end

      it "refuses any other value, since the databases compare JSON differently" do
        refusal = "#{todo}.value is a Hash[String, untyped] column, which where matches only to nil. " \
                  "Match its contents with an SQL string."

        assert_equal(
          [refusal] * 4,
          [{}, { "a" => 1 }, [nil], {}..{}].map { |value| mismatch(column(:json, nullable: true), value) }
        )
      end
    end

    it "checks each element of an array" do
      assert_nil mismatch(column(:integer), [1, 2])
      assert_equal "#{todo}.value is Integer, not \"2\" (String)", mismatch(column(:integer), [1, "2"])
    end

    it "checks each end of a range" do
      assert_nil mismatch(column(:integer), 1..5)
      assert_equal "#{todo}.value is Integer, not 5.5 (Float)", mismatch(column(:integer), 1..5.5)
    end

    it "leaves an open end of a range unchecked, even on a column that isn't nullable" do
      assert_nil mismatch(column(:integer), 1..)
      assert_nil mismatch(column(:integer), ..5)
    end

    describe "on an untyped column" do
      untyped = "#{todo}.value is untyped, which takes any value but a Hash or a nested Array"

      it "takes any other value, nil included" do
        assert_nil mismatch(column(:untyped), [1, "two", :three, nil, Object.new])
      end

      it "refuses a Hash, which the driver can't bind as one value" do
        hash = { id: 1 }

        assert_equal "#{untyped}, not #{hash.inspect} (Hash)", mismatch(column(:untyped), hash)
      end

      it "refuses a nested array, which the driver would spread across placeholders" do
        assert_equal "#{untyped}, not [2, 3] (Array)", mismatch(column(:untyped), [1, [2, 3]])
      end

      it "refuses a Hash in an array" do
        hash = { id: 1 }

        assert_equal "#{untyped}, not #{hash.inspect} (Hash)", mismatch(column(:untyped), [hash])
      end

      it "refuses an Array at an end of a range" do
        assert_equal "#{untyped}, not [5] (Array)", mismatch(column(:untyped), ..[5])
      end
    end

    it "takes nil for a nullable column" do
      assert_nil mismatch(column(:integer, nullable: true), nil)
    end

    it "refuses nil for a column that isn't nullable" do
      assert_equal "#{todo}.value is Integer, not nil (NilClass)", mismatch(column(:integer), nil)
    end

    it "checks nil in an array against the column's nullability" do
      assert_nil mismatch(column(:integer, nullable: true), [1, nil])
      assert_equal "#{todo}.value is Integer, not nil (NilClass)", mismatch(column(:integer), [1, nil])
    end

    describe "on a symbol column" do
      let(:priority) { column(:enum, symbols: %i[low high]) }

      it "takes one of its own Symbols" do
        assert_nil mismatch(priority, :low)
      end

      it "refuses a Symbol that isn't one of them" do
        assert_equal "#{todo}.value is :low | :high, not :urgent (Symbol)", mismatch(priority, :urgent)
      end

      it "refuses one of them written as a String" do
        assert_equal "#{todo}.value is :low | :high, not \"low\" (String)", mismatch(priority, "low")
      end

      it "writes a nullable one's type in parentheses" do
        assert_equal "#{todo}.value is (:low | :high)?, not :urgent (Symbol)",
                     mismatch(column(:enum, nullable: true, symbols: %i[low high]), :urgent)
      end
    end

    {
      integer: ["Integer", 1, 1.0],
      float: ["Float", 1.5, "1.5"],
      string: ["String", "Buy milk", :buy_milk],
      bool: ["bool", false, 0],
      date: ["Date", Date.new(2026, 10, 20), Time.utc(2026, 10, 20)],
      time: ["Time", Time.utc(2026, 10, 18, 9, 30), Date.new(2026, 10, 18)],
      uuid: ["uuid", "0b9d5f2e-7c4a-4e1b-9f3d-2a6c8e0b1d4f", :id],
      int32: ["int32", 1, 1.0],
      int16: ["int16", 1, "1"]
    }.each do |type, (written, taken, refused)|
      describe "on a #{written} column" do
        it "takes #{taken.inspect}" do
          assert_nil mismatch(column(type), taken)
        end

        it "refuses #{refused.inspect}" do
          assert_equal "#{todo}.value is #{written}, not #{refused.inspect} (#{refused.class})",
                       mismatch(column(type), refused)
        end

        it "writes a nullable one's type with ?" do
          assert_equal "#{todo}.value is #{written}?, not #{refused.inspect} (#{refused.class})",
                       mismatch(column(type, nullable: true), refused)
        end
      end
    end

    it "takes an Integer for a Float column" do
      assert_nil mismatch(column(:float), 1)
    end

    it "takes Infinity and -Infinity for a Float column" do
      assert_nil mismatch(column(:float), [Float::INFINITY, -Float::INFINITY])
    end

    it "refuses NaN for a Float column, which SQLite stores as NULL" do
      assert_equal "#{todo}.value is Float, not NaN (Float)", mismatch(column(:float), Float::NAN)
    end

    it "takes true for a bool column" do
      assert_nil mismatch(column(:bool), true)
    end

    it "refuses a DateTime for a Date column" do
      date_time = DateTime.new(2026, 10, 20)

      assert_equal "#{todo}.value is Date, not #{date_time.inspect} (DateTime)", mismatch(column(:date), date_time)
    end

    it "takes a uuid in upper case" do
      assert_nil mismatch(column(:uuid), "0B9D5F2E-7C4A-4E1B-9F3D-2A6C8E0B1D4F")
    end

    it "refuses a String that isn't a uuid's 8-4-4-4-12 hex digits for a uuid column" do
      refused = %W[nope 0b9d5f2e7c4a4e1b9f3d2a6c8e0b1d4f 0b9d5f2e-7c4a-4e1b-9f3d-2a6c8e0b1d4g
                   0b9d5f2e-7c4a-4e1b-9f3d-2a6c8e0b1d4f\n]

      assert_equal(
        refused.map { |value| "#{todo}.value is uuid, not #{value.inspect} (String)" },
        refused.map { |value| mismatch(column(:uuid), value) }
      )
    end

    {
      int32: [-2_147_483_648, 2_147_483_647],
      int16: [-32_768, 32_767]
    }.each do |type, (least, most)|
      it "takes an #{type} from #{least} to #{most}" do
        assert_nil mismatch(column(type), [least, most])
      end

      it "refuses an #{type} outside #{least} to #{most}" do
        assert_equal ["#{todo}.value is #{type}, not #{least - 1} (Integer)",
                      "#{todo}.value is #{type}, not #{most + 1} (Integer)"],
                     [mismatch(column(type), least - 1), mismatch(column(type), most + 1)]
      end
    end
  end

  describe ".write_mismatch" do
    def write_mismatch(column, value) = Skyward::ORM::Tables::Values.write_mismatch(TablesFixtures::Todo, column, value)

    describe "on a JSON column" do
      json = "#{todo}.value is Hash[String, untyped]"

      it "takes a Hash with String keys and JSON values at every level" do
        value = {
          "nothing" => nil,
          "flags" => [true, false],
          "numbers" => [1, 2**70, -0.5, 1e300],
          "text" => "ü",
          "nested" => { "list" => [{ "deep" => {} }, []] }
        }

        assert_nil write_mismatch(column(:json), value)
      end

      it "takes nil for a nullable one" do
        assert_nil write_mismatch(column(:json, nullable: true), nil)
      end

      it "refuses nil for one that isn't nullable" do
        assert_equal "#{json}, not nil (NilClass)", write_mismatch(column(:json), nil)
      end

      it "refuses anything but a Hash, writing a nullable one's type with ?" do
        assert_equal ["#{json}, not [] (Array)", "#{json}?, not \"{}\" (String)"],
                     [write_mismatch(column(:json), []), write_mismatch(column(:json, nullable: true), "{}")]
      end

      it "names a key that isn't a String, and where it is" do
        assert_equal ["#{json}, not :status (Symbol) as a key of value",
                      "#{json}, not 1 (Integer) as a key of value[\"meta\"][0]"],
                     [write_mismatch(column(:json), { status: "pending" }),
                      write_mismatch(column(:json), { "meta" => [{ 1 => "one" }] })]
      end

      {
        "a Symbol" => :pending,
        "a Time" => Time.utc(2026, 11, 11),
        "a Date" => Date.new(2026, 11, 11),
        "a Rational" => Rational(1, 3),
        "NaN" => Float::NAN,
        "Infinity" => Float::INFINITY,
        "-Infinity" => -Float::INFINITY
      }.each do |name, refused|
        it "refuses #{name}, naming the first value JSON doesn't hold and where it is" do
          value = { "ok" => 1, "events" => [{ "at" => 1 }, { "at" => refused, "then" => :later }] }

          assert_equal "#{json}, not #{refused.inspect} (#{refused.class}) at value[\"events\"][1][\"at\"]",
                       write_mismatch(column(:json), value)
        end
      end
    end

    it "takes one value its column's type takes" do
      assert_nil write_mismatch(column(:string), "Buy milk")
    end

    it "checks it as the type does, refusing nil for a column that isn't nullable" do
      assert_equal "#{todo}.value is String, not nil (NilClass)", write_mismatch(column(:string), nil)
    end

    it "refuses an Array, whose elements the type would take" do
      assert_equal "#{todo}.value is String, not [\"c\"] (Array)", write_mismatch(column(:string), ["c"])
    end

    it "refuses an empty Array" do
      assert_equal "#{todo}.value is String, not [] (Array)", write_mismatch(column(:string), [])
    end

    it "refuses a Range, whose ends the type would take" do
      assert_equal "#{todo}.value is String, not \"x\"..\"y\" (Range)", write_mismatch(column(:string), "x".."y")
    end

    it "refuses a value its column can't hold" do
      assert_equal "#{todo}.value is int16, not 32768 (Integer)", write_mismatch(column(:int16), 32_768)
    end

    describe "on an untyped column" do
      untyped = "#{todo}.value is untyped, which takes any one value but an Array, a Hash or a Range"

      it "takes any other value, nil included" do
        assert_nil write_mismatch(column(:untyped), nil)
      end

      it "refuses an Array, which the driver would spread across placeholders" do
        assert_equal "#{untyped}, not [] (Array)", write_mismatch(column(:untyped), [])
      end

      it "refuses a Hash" do
        hash = { id: 1 }

        assert_equal "#{untyped}, not #{hash.inspect} (Hash)", write_mismatch(column(:untyped), hash)
      end

      it "refuses a Range, which the driver can't bind" do
        assert_equal "#{untyped}, not 1..2 (Range)", write_mismatch(column(:untyped), 1..2)
      end
    end
  end
end
