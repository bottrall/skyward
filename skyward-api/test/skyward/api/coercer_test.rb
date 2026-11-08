# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Coercer do
  types = Skyward::Types

  integer = types::Scalar.new(name: :integer)
  float = types::Scalar.new(name: :float)
  string = types::Scalar.new(name: :string)
  bool = types::Scalar.new(name: :bool)
  date = types::Scalar.new(name: :date)
  time = types::Scalar.new(name: :time)
  priority = types::Enum.new(symbols: %i[low normal high])

  def coerce(type, raw, strings: false) = Skyward::API::Coercer.compile(type, strings:).call(raw, "body")

  def ok(value) = Skyward::API::Coercer::Ok.new(value:)

  def invalid(*errors)
    Skyward::API::Coercer::Invalid.new(
      errors: errors.map { |at, message| Skyward::API::Coercer::Error.new(at:, message:) }
    )
  end

  def mismatch(message) = invalid(["body", message])

  def cpu_seconds
    start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    yield
    Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - start
  end

  describe ".compile" do
    describe "Integer" do
      it "accepts an Integer" do
        assert_equal ok(42), coerce(integer, 42)
      end

      it "parses a String of digits from a path or query" do
        assert_equal ok(-42), coerce(integer, "-42", strings: true)
      end

      it "refuses a String that isn't only digits" do
        assert_equal mismatch('expected Integer, got "4.0"'), coerce(integer, "4.0", strings: true)
      end

      it "refuses a String in a body" do
        assert_equal mismatch('expected Integer, got "42"'), coerce(integer, "42")
      end

      it "refuses a Float" do
        assert_equal mismatch("expected Integer, got 4.0"), coerce(integer, 4.0)
      end
    end

    describe "Float" do
      it "accepts an Integer as a Float" do
        assert_equal ok(2.0), coerce(float, 2)
      end

      it "accepts a Float" do
        assert_equal ok(2.5), coerce(float, 2.5)
      end

      it "parses a String from a path or query with Float()" do
        assert_equal ok(2500.0), coerce(float, "2.5e3", strings: true)
      end

      it "refuses a String Float() can't parse" do
        assert_equal mismatch('expected Float, got "lots"'), coerce(float, "lots", strings: true)
      end

      it "refuses a String in a body" do
        assert_equal mismatch('expected Float, got "2.5"'), coerce(float, "2.5")
      end

      it "refuses a number too large to be finite" do
        assert_equal mismatch('expected Float, got "1e400"'), coerce(float, "1e400", strings: true)
      end

      it "writes an infinite number in its message" do
        assert_equal mismatch("expected Float, got Infinity"), coerce(float, Float::INFINITY)
      end
    end

    describe "bool" do
      it "accepts false" do
        assert_equal ok(false), coerce(bool, false)
      end

      it "parses true, false, 1 and 0 from a path or query" do
        assert_equal ok([true, false, true, false]),
                     coerce(types::ArrayOf.new(type: bool), %w[true false 1 0], strings: true)
      end

      it "refuses any other String from a path or query" do
        assert_equal mismatch('expected bool, got "yes"'), coerce(bool, "yes", strings: true)
      end

      it "refuses a String in a body" do
        assert_equal mismatch('expected bool, got "true"'), coerce(bool, "true")
      end
    end

    describe "String" do
      it "accepts a String" do
        assert_equal ok("Ship it"), coerce(string, "Ship it")
      end

      it "refuses a number" do
        assert_equal mismatch("expected String, got 1"), coerce(string, 1)
      end

      it "refuses a query key given more than once" do
        assert_equal mismatch('expected String, got ["a","b"]'), coerce(string, %w[a b], strings: true)
      end
    end

    describe "Date" do
      it "parses YYYY-MM-DD" do
        assert_equal ok(Date.new(2026, 2, 28)), coerce(date, "2026-02-28")
      end

      it "refuses anything but a String" do
        assert_equal mismatch("expected Date (YYYY-MM-DD), got 20260228"), coerce(date, 20_260_228)
      end

      it "refuses another format" do
        assert_equal mismatch('expected Date (YYYY-MM-DD), got "next tuesday"'), coerce(date, "next tuesday")
      end

      it "refuses a day that doesn't exist" do
        assert_equal mismatch('expected Date (YYYY-MM-DD), got "2026-02-30"'), coerce(date, "2026-02-30")
      end
    end

    describe "Time" do
      it "parses ISO 8601 in UTC" do
        assert_equal ok(Time.utc(2026, 10, 18, 9, 30)), coerce(time, "2026-10-18T09:30:00Z")
      end

      it "parses a fraction of a second and an offset" do
        expected = Time.new(2026, 10, 18, 9, 30, Rational("7.125"), "-05:30")

        assert_equal ok(expected), coerce(time, "2026-10-18T09:30:07.125-05:30")
      end

      it "cuts a fraction to nanoseconds" do
        expected = Time.utc(2026, 10, 18, 9, 30, Rational(7_123_456_789, 10**9))

        assert_equal ok(expected), coerce(time, "2026-10-18T09:30:07.1234567891234Z")
      end

      it "keeps the offset" do
        assert_equal 19_800, coerce(time, "2026-10-18T09:30:00+05:30").value.utc_offset
      end

      it "refuses anything but a String" do
        assert_equal mismatch("expected Time (ISO 8601), got 1"), coerce(time, 1)
      end

      it "refuses a time without seconds" do
        assert_equal mismatch('expected Time (ISO 8601), got "2026-10-18T09:30Z"'), coerce(time, "2026-10-18T09:30Z")
      end

      it "refuses a time without a zone" do
        assert_equal mismatch('expected Time (ISO 8601), got "2026-10-18T09:30:00"'),
                     coerce(time, "2026-10-18T09:30:00")
      end

      it "refuses an hour that doesn't exist" do
        assert_equal mismatch('expected Time (ISO 8601), got "2026-10-18T24:00:00Z"'),
                     coerce(time, "2026-10-18T24:00:00Z")
      end

      it "refuses a day that doesn't exist" do
        assert_equal mismatch('expected Time (ISO 8601), got "2026-02-30T09:30:00Z"'),
                     coerce(time, "2026-02-30T09:30:00Z")
      end
    end

    describe "untyped" do
      it "takes anything as it is" do
        assert_equal ok({ "title" => 1 }), coerce(types::Scalar.new(name: :untyped), { "title" => 1 })
      end

      it "refuses a query key given more than once" do
        assert_equal mismatch('expected untyped, got ["a","b"]'),
                     coerce(types::Scalar.new(name: :untyped), %w[a b], strings: true)
      end
    end

    describe "a literal" do
      it "parses an Integer from a path or query" do
        assert_equal ok(1), coerce(types::Literal.new(value: 1), "1", strings: true)
      end

      it "accepts a String" do
        assert_equal ok("ok"), coerce(types::Literal.new(value: "ok"), "ok")
      end

      it "accepts nil as nil" do
        assert_equal ok(nil), coerce(types::Literal.new(value: nil), nil)
      end

      it "parses a boolean from a path or query" do
        assert_equal ok(true), coerce(types::Literal.new(value: true), "1", strings: true)
      end

      it "refuses a value of another type" do
        assert_equal mismatch('expected 1, got "1"'), coerce(types::Literal.new(value: 1), "1")
      end

      it "refuses another value of its type" do
        assert_equal mismatch("expected 1, got 2"), coerce(types::Literal.new(value: 1), 2)
      end
    end

    describe "a symbol union" do
      it "takes a symbol's name and gives the Symbol" do
        assert_equal ok(:low), coerce(priority, "low")
      end

      it "refuses any other String" do
        assert_equal mismatch('expected :low | :normal | :high, got "urgent"'), coerce(priority, "urgent")
      end

      it "refuses a Symbol's name that isn't a String" do
        assert_equal mismatch("expected :low | :normal | :high, got 1"), coerce(priority, 1)
      end
    end

    describe "a nullable type" do
      it "accepts null" do
        assert_equal ok(nil), coerce(types::Nullable.new(type: integer), nil)
      end

      it "coerces anything else as the type" do
        assert_equal ok(1), coerce(types::Nullable.new(type: integer), "1", strings: true)
      end
    end

    describe "an Array" do
      let(:integers) { types::ArrayOf.new(type: integer) }
      let(:max) { Skyward::API::Coercer::MAX_ERRORS }

      it "coerces each item" do
        assert_equal ok([1, 2]), coerce(integers, %w[1 2], strings: true)
      end

      it "takes one value from a path or query as a one-item array" do
        assert_equal ok([1]), coerce(integers, "1", strings: true)
      end

      it "refuses one value in a body" do
        assert_equal mismatch('expected Array[Integer], got "1"'), coerce(integers, "1")
      end

      it "refuses anything else" do
        assert_equal mismatch("expected Array[Integer], got 1"), coerce(integers, 1)
      end

      it "reports every item that doesn't fit, at its index" do
        expected = invalid(["body[1]", 'expected Integer, got "x"'], ["body[2]", "expected Integer, got null"])

        assert_equal expected, coerce(integers, [1, "x", nil])
      end

      it "reports no more than MAX_ERRORS items" do
        assert_equal max, coerce(integers, Array.new(max + 1)).errors.size
      end

      it "doesn't coerce the items after MAX_ERRORS problems" do
        built = []
        counted = Data.define(:title) do
          define_method(:initialize) do |title:|
            built << title
            super(title:)
          end
        end
        fields = [types::Field.new(name: :title, type: string, required: true)]
        todos = types::ArrayOf.new(type: types::Named.new(name: "Todo", klass: counted, fields:))
        coerce(todos, [*Array.new(max, 1), { "title" => "late" }])

        assert_empty built
      end
    end

    describe "a record" do
      let(:record) do
        types::Record.new(
          fields: [
            types::Field.new(name: :priority, type: priority, required: true),
            types::Field.new(name: :due_on, type: types::Nullable.new(type: date), required: true),
            types::Field.new(name: :page, type: integer, required: false)
          ]
        )
      end

      it "makes a Hash with Symbol keys, ignoring undeclared keys" do
        expected = ok({ priority: :low, due_on: Date.new(2026, 2, 28), page: 2 })

        assert_equal expected, coerce(record, { "priority" => "low", "due_on" => "2026-02-28", "page" => 2, "x" => 1 })
      end

      it "gives an absent nullable field nil and leaves out an absent optional one" do
        assert_equal ok({ priority: :low, due_on: nil }), coerce(record, { "priority" => "low" })
      end

      it "refuses anything but an object" do
        message = "expected { priority: :low | :normal | :high, due_on: Date?, ?page: Integer }, got []"

        assert_equal mismatch(message), coerce(record, [])
      end

      it "reports every field that doesn't fit, at its name" do
        expected = invalid(["body.priority", "is required"], ["body.page", 'expected Integer, got "2"'])

        assert_equal expected, coerce(record, { "page" => "2" })
      end

      it "doesn't coerce the fields after MAX_ERRORS problems" do
        built = []
        counted = Data.define(:title) do
          define_method(:initialize) do |title:|
            built << title
            super(title:)
          end
        end
        title = [types::Field.new(name: :title, type: string, required: true)]
        todo = types::Named.new(name: "Todo", klass: counted, fields: title)
        max = Skyward::API::Coercer::MAX_ERRORS
        fields = Array.new(max) { |index| types::Field.new(name: :"f#{index}", type: integer, required: true) }
        record = types::Record.new(fields: [*fields, types::Field.new(name: :todo, type: todo, required: true)])
        coerce(record, { "todo" => { "title" => "late" } })

        assert_empty built
      end
    end

    describe "a class with typed readers" do
      let(:todo_class) { Data.define(:title, :done) }
      let(:todo) do
        types::Named.new(
          name: "Todo",
          klass: todo_class,
          fields: [
            types::Field.new(name: :title, type: string, required: true),
            types::Field.new(name: :done, type: types::Nullable.new(type: bool), required: true)
          ]
        )
      end

      it "builds it with new(**fields)" do
        assert_equal ok(todo_class.new(title: "Ship it", done: nil)), coerce(todo, { "title" => "Ship it" })
      end

      it "refuses anything but an object, by the class's name" do
        assert_equal mismatch('expected Todo, got "Ship it"'), coerce(todo, "Ship it")
      end
    end

    describe "a union" do
      let(:union) { types::Union.new(types: [integer, string]) }

      it "takes the first member that fits" do
        assert_equal ok(1), coerce(union, "1", strings: true)
      end

      it "takes a later member when an earlier one doesn't fit" do
        assert_equal ok("one"), coerce(union, "one", strings: true)
      end

      it "refuses what no member fits, naming them all" do
        assert_equal mismatch("expected Integer | String, got true"), coerce(union, true)
      end

      it "stops coercing a member at its first problem" do
        built = []
        counted = Data.define(:title) do
          define_method(:initialize) do |title:|
            built << title
            super(title:)
          end
        end
        fields = [types::Field.new(name: :title, type: string, required: true)]
        todos = types::ArrayOf.new(type: types::Named.new(name: "Todo", klass: counted, fields:))
        coerce(types::Union.new(types: [todos, string]), [1, { "title" => "late" }])

        assert_empty built
      end

      it "stops coercing a member's fields at its first problem" do
        built = []
        counted = Data.define(:title) do
          define_method(:initialize) do |title:|
            built << title
            super(title:)
          end
        end
        title = [types::Field.new(name: :title, type: string, required: true)]
        todo = types::Named.new(name: "Todo", klass: counted, fields: title)
        note = types::Record.new(
          fields: [
            types::Field.new(name: :text, type: string, required: true),
            types::Field.new(name: :todo, type: todo, required: true)
          ]
        )
        coerce(types::Union.new(types: [note, string]), { "todo" => { "title" => "late" } })

        assert_empty built
      end

      it "reports the same value at each place no member fits it" do
        expected = invalid(
          ["body[0]", "expected Integer | String, got true"],
          ["body[1]", "expected Integer | String, got true"]
        )

        assert_equal expected, coerce(types::ArrayOf.new(type: union), [true, true])
      end

      it "coerces a value once for members that hold equal unions" do
        built = []
        counted = Data.define(:title) do
          define_method(:initialize) do |title:|
            built << title
            super(title:)
          end
        end
        title = [types::Field.new(name: :title, type: string, required: true)]
        members = %i[due page].map do |name|
          todo = types::Union.new(types: [types::Named.new(name: "Todo", klass: counted, fields: title), string])
          types::Record.new(
            fields: [
              types::Field.new(name: :todo, type: todo, required: true),
              types::Field.new(name:, type: integer, required: true)
            ]
          )
        end
        result = coerce(types::Union.new(types: members), { "todo" => { "title" => "Ship it" }, "page" => 2 })

        assert_equal [["Ship it"], "Ship it", 2], [built, result.value.fetch(:todo).title, result.value.fetch(:page)]
      end

      it "costs no more for an Array of a union the deeper it nests" do
        nested = 99.times.reduce(integer) do |inner, _|
          types::Union.new(types: [types::ArrayOf.new(type: inner), string])
        end
        coercer = Skyward::API::Coercer.compile(types::ArrayOf.new(type: nested), strings: false)
        body = 99.times.reduce(Array.new(100_000, "x")) { |inner, _| [inner] }

        assert_operator cpu_seconds { coercer.call(body, "body") }, :<, 0.05
      end

      it "costs no more for overlapping records the deeper they nest" do
        names = %i[b c]
        nested = 15.times.reduce(integer) do |inner, _|
          records = names.map do |name|
            types::Record.new(
              fields: [
                types::Field.new(name: :a, type: inner, required: true),
                types::Field.new(name:, type: integer, required: true)
              ]
            )
          end
          types::Union.new(types: records)
        end
        coercer = Skyward::API::Coercer.compile(nested, strings: false)
        body = 15.times.reduce("x") { |inner, _| { "a" => inner } }

        assert_operator cpu_seconds { coercer.call(body, "body") }, :<, 0.1
      end

      it "costs no more for overlapping Arrays the deeper they nest" do
        nested = 15.times.reduce(integer) do |inner, _|
          either = types::Union.new(types: [inner, string])
          types::Union.new(types: [types::ArrayOf.new(type: inner), types::ArrayOf.new(type: either)])
        end
        coercer = Skyward::API::Coercer.compile(nested, strings: false)
        body = 15.times.reduce(1.5) { |inner, _| [inner] }

        assert_operator cpu_seconds { coercer.call(body, "body") }, :<, 0.1
      end
    end

    describe "messages" do
      let(:fields) do
        Array.new(20) { |index| types::Field.new(name: :"description#{index}", type: string, required: true) }
      end

      it "write a Date or Time inside another type without its format" do
        dates = types::ArrayOf.new(type: types::Union.new(types: [date, time]))

        assert_equal mismatch("expected Array[Date | Time], got 1"), coerce(dates, 1)
      end

      it "write a type of MAX_EXPECTED characters in full" do
        long = "a" * (Skyward::API::Coercer::MAX_EXPECTED - 2)

        assert_equal mismatch("expected \"#{long}\", got 1"), coerce(types::Literal.new(value: long), 1)
      end

      it "cut a longer type to MAX_EXPECTED characters, ending with …" do
        long = "a" * (Skyward::API::Coercer::MAX_EXPECTED - 1)

        assert_equal mismatch("expected \"#{long.chop}…, got 1"), coerce(types::Literal.new(value: long), 1)
      end

      it "cut a large union in every message, so a 422 stays proportional to its body" do
        records = types::Union.new(types: [types::Record.new(fields:), types::Record.new(fields: fields.reverse)])
        max = Skyward::API::Coercer::MAX_ERRORS
        messages = coerce(types::ArrayOf.new(type: records), Array.new(max, 1)).errors.map(&:message)

        assert_equal max, messages.size
        assert_empty messages.grep_v(/\Aexpected \{ .{197}…, got 1\z/)
      end

      it "cut a large record" do
        assert_match(/\Aexpected \{ .{197}…, got 1\z/, coerce(types::Record.new(fields:), 1).errors.first.message)
      end

      it "write bytes that aren't UTF-8 as replacement characters" do
        assert_equal mismatch("expected Integer, got \"caf\u{FFFD}\""), coerce(integer, "caf\xE9", strings: true)
      end

      it "write a value nested past JSON.generate's default limit" do
        nested = Array.new(100).reduce([]) { |inner, _| [inner] }

        assert_instance_of Skyward::API::Coercer::Invalid, coerce(string, nested)
      end

      it "write a nullable union of types in parentheses" do
        nullable = types::ArrayOf.new(type: types::Nullable.new(type: types::Union.new(types: [integer, string])))

        assert_equal mismatch("expected Array[(Integer | String)?], got 1"), coerce(nullable, 1)
      end

      it "write a nullable union in parentheses" do
        nullable = types::ArrayOf.new(type: types::Nullable.new(type: priority))

        assert_equal mismatch("expected Array[(:low | :normal | :high)?], got 1"), coerce(nullable, 1)
      end

      it "write a nullable single symbol without them" do
        nullable = types::ArrayOf.new(type: types::Nullable.new(type: types::Enum.new(symbols: [:low])))

        assert_equal mismatch("expected Array[:low?], got 1"), coerce(nullable, 1)
      end
    end
  end

  describe ".absent" do
    it "gives nothing for an optional keyword" do
      assert_nil Skyward::API::Coercer.absent(integer, false, "query.limit")
    end

    it "gives nil for a required nullable keyword" do
      assert_equal ok(nil), Skyward::API::Coercer.absent(types::Nullable.new(type: integer), true, "query.limit")
    end

    it "says a required keyword is required" do
      assert_equal invalid(["query.limit", "is required"]), Skyward::API::Coercer.absent(integer, true, "query.limit")
    end
  end

  describe ".combine" do
    it "gives each value by its name" do
      assert_equal ok({ id: 1, done: nil }), Skyward::API::Coercer.combine({ id: ok(1), done: ok(nil) })
    end

    it "gives every error when any value is invalid" do
      results = { id: invalid(["path.id", "a"]), done: ok(nil), limit: invalid(["query.limit", "b"]) }

      assert_equal invalid(["path.id", "a"], ["query.limit", "b"]), Skyward::API::Coercer.combine(results)
    end
  end
end
