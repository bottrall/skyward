# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Writers do
  types = Skyward::Types
  integer = types::Scalar.new(name: :integer)
  string = types::Scalar.new(name: :string)
  untyped = types::Scalar.new(name: :untyped)
  priority = types::Enum.new(symbols: %i[low high])

  user = Data.define(:id, :name, :password_hash) do
    def to_h = raise("to_h must never be called")
  end
  named_user = types::Named.new(
    name: "User",
    klass: user,
    fields: [types::Field.new(name: :id, type: integer, required: true)]
  )

  define_method(:writer) { |type| Skyward::API::Writers.writer(type) }
  define_method(:write) { |type, value| writer(type).write.call(value, "") }

  def misfit(at, expected, got) = Skyward::API::Writers::Misfit.new(at:, expected:, got:)

  def field(name, type, required: true) = Skyward::Types::Field.new(name:, type:, required:)

  describe ".writer" do
    describe "a scalar" do
      it "writes an Integer, a Float, a String and a bool as themselves" do
        written = [[integer, 42], [types::Scalar.new(name: :float), 1.5], [string, "Ship it"],
                   [types::Scalar.new(name: :bool), false]].map { |type, value| write(type, value) }

        assert_equal [42, 1.5, "Ship it", false], written
      end

      it "writes a Date as YYYY-MM-DD" do
        assert_equal "2026-10-18", write(types::Scalar.new(name: :date), Date.new(2026, 10, 18))
      end

      it "writes a DateTime typed Date as its date alone" do
        assert_equal "2026-10-18", write(types::Scalar.new(name: :date), DateTime.new(2026, 10, 18, 9, 30))
      end

      it "writes a Time in UTC, as ISO 8601 with six fractional digits" do
        time = Time.new(2026, 10, 18, 11, 30, Rational(123_456, 1_000_000), "+02:00")

        assert_equal "2026-10-18T09:30:00.123456Z", write(types::Scalar.new(name: :time), time)
      end

      it "names each by its RBS type" do
        names = %i[integer float string bool date time untyped].map { |name| writer(types::Scalar.new(name:)).name }

        assert_equal %w[Integer Float String bool Date Time untyped], names
      end

      it "fits only a value of its class" do
        given = { integer: 1.0, float: 1, string: :ship, bool: nil, date: Time.now, time: Date.today }

        assert_equal([false] * 6, given.map { |name, value| writer(types::Scalar.new(name:)).fits.call(value) })
      end

      it "answers a value that doesn't fit with a misfit naming the type and the value" do
        assert_equal misfit("", "Integer", "nil"), write(integer, nil)
      end

      it "names a value that doesn't fit by its class unless it's a scalar, so a message never carries its content" do
        got = ["secret", Object.new, :ship, 1.5, true].map { |value| write(integer, value).got }

        assert_equal ["String", "Object", ":ship", "1.5", "true"], got
      end
    end

    describe "untyped" do
      it "fits anything" do
        assert writer(untyped).fits.call(Object.new)
      end

      it "writes scalars as themselves, a Symbol as its name, and dates and times as their scalars do" do
        values = [nil, true, 42, 1.5, "Ship it", :low, Date.new(2026, 10, 18), Time.utc(2026, 10, 18, 9, 30)]
        expected = [nil, true, 42, 1.5, "Ship it", "low", "2026-10-18", "2026-10-18T09:30:00.000000Z"]

        assert_equal(expected, values.map { |value| write(untyped, value) })
      end

      it "writes a Hash and an Array recursively" do
        assert_equal(
          { tags: ["low"], due: { on: "2026-10-18" } },
          write(untyped, { tags: [:low], due: { on: Date.new(2026, 10, 18) } })
        )
      end

      it "writes anything else through to_h" do
        point = Struct.new(:x, :at)

        assert_equal({ x: 1, at: "low" }, write(untyped, point.new(1, :low)))
      end

      it "answers something without to_h with a misfit where it was found" do
        assert_equal misfit(".todos[1]", "something with to_h", "Object"), write(untyped, { todos: [1, Object.new] })
      end
    end

    describe "a literal" do
      it "writes the one value it fits" do
        assert_equal ["done", misfit("", '"done"', "String")],
                     [write(types::Literal.new(value: "done"), "done"),
                      write(types::Literal.new(value: "done"), "open")]
      end

      it "doesn't fit an equal value of another class" do
        refute writer(types::Literal.new(value: 1)).fits.call(1.0)
      end

      it "writes nil, named nil" do
        nil_writer = writer(types::Literal.new(value: nil))

        assert_equal [nil, "nil"], [nil_writer.write.call(nil, ""), nil_writer.name]
      end
    end

    describe "an enum" do
      it "writes a Symbol it lists as its name" do
        assert_equal "high", write(priority, :high)
      end

      it "doesn't fit a Symbol it doesn't list, or its name as a String" do
        assert_equal [misfit("", ":low | :high", ":urgent"), misfit("", ":low | :high", "String")],
                     [write(priority, :urgent), write(priority, "low")]
      end
    end

    describe "a nullable type" do
      it "writes nil as nil, and anything else as its type" do
        assert_equal([nil, 42], [nil, 42].map { |value| write(types::Nullable.new(type: integer), value) })
      end

      it "fits nil, and what its type fits" do
        nullable = writer(types::Nullable.new(type: integer))

        assert_equal([true, false], [nil, "42"].map { |value| nullable.fits.call(value) })
      end

      it "is named with a ?, grouping a union or an enum of several symbols" do
        names = [integer, priority, types::Enum.new(symbols: [:low]),
                 types::Union.new(types: [integer, string])].map do |type|
          writer(types::Nullable.new(type:)).name
        end

        assert_equal ["Integer?", "(:low | :high)?", ":low?", "(Integer | String)?"], names
      end
    end

    describe "an array" do
      let(:tags) { types::ArrayOf.new(type: priority) }

      it "writes each item as its type" do
        assert_equal %w[low high], write(tags, %i[low high])
      end

      it "answers an item that doesn't fit with a misfit at its index" do
        assert_equal misfit("[1]", ":low | :high", ":urgent"), write(tags, %i[low urgent])
      end

      it "doesn't fit anything but an Array, and is named Array[T]" do
        assert_equal [false, "Array[:low | :high]"], [writer(tags).fits.call({}), writer(tags).name]
      end
    end

    describe "a Hash" do
      let(:lists) { types::HashOf.new(type: types::ArrayOf.new(type: named_user)) }

      it "writes each value as its type, with String or Symbol keys as strings" do
        written = write(lists, { "admins" => [user.new(1, "Ada", "x")], guests: [] })

        assert_equal({ "admins" => [{ id: 1 }], "guests" => [] }, written)
      end

      it "answers a value that doesn't fit with a misfit at its key, quoted as JSON" do
        assert_equal misfit('["a.b"][0].id', "Integer", "String"),
                     write(lists, { "a.b" => [user.new("1", "Ada", "x")] })
      end

      it "fits only a Hash whose keys are Strings or Symbols, and is named Hash[String, T]" do
        fits = [{}, { "a" => [], b: [] }, { 1 => [] }, []].map { |value| writer(lists).fits.call(value) }

        assert_equal [[true, true, false, false], "Hash[String, Array[User]]"], [fits, writer(lists).name]
      end
    end

    describe "a record" do
      let(:record) { types::Record.new(fields: [field(:id, integer), field(:note, string, required: false)]) }

      it "writes the keys it declares from a Hash, and drops the rest" do
        assert_equal({ id: 1, note: "soon" }, write(record, { id: 1, note: "soon", password_hash: "x" }))
      end

      it "leaves out an optional key that's absent" do
        assert_equal({ id: 1 }, write(record, { id: 1 }))
      end

      it "answers a required key that's absent with a misfit" do
        assert_equal misfit(".id", "Integer", "nothing"), write(record, { note: "soon" })
      end

      it "answers a value that doesn't fit with a misfit at its key" do
        assert_equal misfit(".note", "String", "nil"), write(record, { id: 1, note: nil })
      end

      it "doesn't fit anything but a Hash, and is named like RBS" do
        assert_equal [false, "{ id: Integer, ?note: String }"], [writer(record).fits.call([]), writer(record).name]
      end
    end

    describe "a class with typed readers" do
      it "writes only the readers it declares, never through to_h" do
        assert_equal({ id: 1 }, write(named_user, user.new(1, "Ada", "$2a$12$secret")))
      end

      it "answers a reader whose value doesn't fit with a misfit at the reader" do
        assert_equal misfit(".id", "Integer", "String"), write(named_user, user.new("1", "Ada", "x"))
      end

      it "fits only an instance of its class, and is named by it" do
        assert_equal [false, "User"], [writer(named_user).fits.call({ id: 1 }), writer(named_user).name]
      end
    end

    describe "a union" do
      it "writes a value with the first member it fits" do
        union = types::Union.new(types: [named_user, types::Record.new(fields: [field(:id, string)])])

        assert_equal [{ id: 1 }, { id: "a" }], [write(union, user.new(1, "Ada", "x")), write(union, { id: "a" })]
      end

      it "writes a value with a later record that fits it by its fields" do
        ok = types::Literal.new(value: true)
        failed = types::Literal.new(value: false)
        union = types::Union.new(
          types: [
            types::Record.new(fields: [field(:ok, ok), field(:id, integer)]),
            types::Record.new(fields: [field(:ok, failed), field(:error, string)])
          ]
        )

        assert_equal({ ok: false, error: "nope" }, write(union, { ok: false, error: "nope" }))
      end

      it "writes a value with a later array that fits its items" do
        union = types::Union.new(types: [types::ArrayOf.new(type: integer), types::ArrayOf.new(type: string)])

        assert_equal %w[a b], write(union, %w[a b])
      end
    end
  end

  describe ".union" do
    let(:union) { Skyward::API::Writers.union([writer(integer), writer(priority)]) }

    it "fits what any member fits, and is named by its members" do
      assert_equal [true, true, false, "Integer | :low | :high"],
                   [union.fits.call(1), union.fits.call(:low), union.fits.call("1"), union.name]
    end

    it "answers a value no member fits with a misfit naming the union" do
      assert_equal misfit(".at", "Integer | :low | :high", "String"), union.write.call("1", ".at")
    end

    it "answers a value only fitting members misfit with the first of their misfits" do
      members = [integer, string].map { |type| writer(types::ArrayOf.new(type:)) }
      arrays = Skyward::API::Writers.union(members)

      assert_equal misfit(".at[0]", "Integer", ":a"), arrays.write.call([:a], ".at")
    end
  end

  describe ".checked" do
    let(:checked) { Skyward::API::Writers.checked("Even", lambda(&:even?), ->(value, at) { [value, at] }) }

    it "writes a value that fits, with where it was found" do
      assert_equal [2, ".count"], checked.write.call(2, ".count")
    end

    it "answers a value that doesn't fit with a misfit" do
      assert_equal misfit(".count", "Even", "3"), checked.write.call(3, ".count")
    end
  end
end
