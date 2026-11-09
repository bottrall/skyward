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
      time: ["Time", Time.utc(2026, 10, 18, 9, 30), Date.new(2026, 10, 18)]
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

    it "takes true for a bool column" do
      assert_nil mismatch(column(:bool), true)
    end

    it "refuses a DateTime for a Date column" do
      date_time = DateTime.new(2026, 10, 20)

      assert_equal "#{todo}.value is Date, not #{date_time.inspect} (DateTime)", mismatch(column(:date), date_time)
    end
  end

  describe ".write_mismatch" do
    def write_mismatch(column, value) = Skyward::ORM::Tables::Values.write_mismatch(TablesFixtures::Todo, column, value)

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
