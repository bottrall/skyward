# frozen_string_literal: true

require "fileutils"
require "test_helper"
require "tmpdir"
require_relative "../fixtures/types/types_fixtures"

# Both READMEs promise that a row read from the database and the same class
# sent as JSON are the same thing. These hold the two gems to it.
describe "Skyward's types" do
  signatures = File.expand_path("../fixtures/types/sig", __dir__)

  let(:directory) { Dir.mktmpdir("skyward-types") }

  after { FileUtils.rm_rf(directory) }

  describe "with the fixture's table" do
    let(:received) { Thread::Queue.new }
    let(:client) do
      app = Skyward.app(signatures:, logger: nil, docs: true) do |builder|
        builder.mount TypesFixtures::EverythingAPI.new(received:)
      end
      Skyward::API::Test.client(app)
    end
    let(:database) { Skyward.connect(TestDatabase.url, signatures:, check: false) }

    # The table comes from the migration Skyward ORM generates for the class,
    # so its columns have the types the ORM maps.
    before do
      changes = Skyward::ORM::Migrations::Diff.changes(
        [TypesFixtures::Everything], database.column_types, database.tables, database.adapter, ->(*) { false }
      )
      script = Skyward::ORM::Migrations::Script.write(changes, database.adapter)
      Skyward::ORM::Migrations::Directory.write(directory, Time.now, "create_everythings", script)
      Skyward.migrate(File.join(directory, Skyward::ORM::Migrations::Directory::PATH))
    end

    describe "a row the API returns and takes back" do
      # A fraction of a second and an offset, so neither side can round the
      # time or lose its zone without the round trip noticing.
      due_at = Time.new(2026, 11, 9, 21, 45, Rational("7.123456"), "+10:30")

      values = {
        count: -42,
        ratio: 0.1,
        title: "Ünïcode \"quoted\" ✓",
        done: true,
        due_on: Date.new(2028, 2, 29),
        due_at:,
        priority: :high,
        settings: {
          "retries" => [{ "delay" => 0.5, "limit" => 2**64, "until" => nil, "on" => false, "headers" => {} }],
          "ünïcode" => "✓"
        }
      }

      # Inserts a row, posts back what the API returned for it, and answers
      # with what the endpoint received and the row the database holds.
      def round_trip(values)
        id = TypesFixtures::Everything.into(TypesFixtures::Everything).insert!(**values).id
        shown = client.get("/everythings/#{id}")

        assert_equal 200, shown.status, shown.body

        posted = client.post("/everythings", json: shown.json)

        assert_equal 204, posted.status, posted.body

        [received.pop(true), TypesFixtures::Everything.find_by(id:)]
      end

      it "is the row the database holds, with its nullable columns filled" do
        nullables = {
          nullable_count: 0,
          nullable_ratio: -2.5e-8,
          nullable_title: "",
          nullable_done: false,
          nullable_due_on: Date.new(1970, 1, 1),
          nullable_due_at: Time.new(1999, 12, 31, 23, 59, Rational("59.999999"), "-03:00"),
          nullable_priority: :low,
          nullable_settings: {}
        }
        got, row = round_trip(values.merge(nullables))

        assert_equal row, got
        assert_equal nullables, got.to_h.slice(*nullables.keys)
      end

      it "is the row the database holds, with its nullable columns nil" do
        got, row = round_trip(values.merge(done: false))

        assert_equal row, got
        assert_equal due_at, got.due_at
      end
    end

    describe "the class's OpenAPI component" do
      # Each column type as Skyward API documents it, from the two READMEs' tables.
      documented = {
        integer: { type: "integer" },
        float: { type: "number" },
        string: { type: "string" },
        bool: { type: "boolean" },
        date: { type: "string", format: "date" },
        time: { type: "string", format: "date-time" },
        json: { type: "object", additionalProperties: {} }
      }

      it "agrees with the ORM's columns on each name, type, nullability and enum" do
        component = client.get("/openapi.json").json.dig(:components, :schemas, :"TypesFixtures.Everything")
        columns = database.column_types.columns(TypesFixtures::Everything)
        expected = columns.to_h do |column|
          type = documented.fetch(column.type) { { type: "string", enum: column.symbols.map(&:name) } }
          schema = if !column.nullable then type
                   elsif column.type == :enum then { anyOf: [type, { type: "null" }] }
                   else type.merge(type: [type.fetch(:type), "null"])
                   end
          [column.name, schema]
        end

        assert_equal expected, component.fetch(:properties)
        assert_equal columns.reject(&:nullable).map { |column| column.name.name }, component.fetch(:required)
      end
    end
  end

  describe "types only one gem reads" do
    # Every type either README maps, written as RBS.
    candidates = [
      "Integer", "Float", "String", "bool", "Date", "Time", ":low | :high",
      "Integer?", "Float?", "String?", "bool?", "Date?", "Time?", "(:low | :high)?",
      "BigDecimal", "Hash[String, untyped]", "Hash[String, Integer]", "Array[Integer]",
      "{ id: Integer }", "TypesFixtures::Item", "TypesFixtures::Item | TypesFixtures::Tag", '"draft"'
    ]

    # The candidates that aren't read by both gems, and which gems read each.
    # Teaching either gem a type moves it in or out of this list, so the test
    # fails until the list says which gems read it.
    known = {
      "BigDecimal" => %i[api],
      "Hash[String, Integer]" => %i[api],
      "Array[Integer]" => %i[api],
      "{ id: Integer }" => %i[api],
      "TypesFixtures::Item" => %i[api],
      "TypesFixtures::Item | TypesFixtures::Tag" => %i[api],
      '"draft"' => %i[api]
    }

    # Whether booting with the type's signatures finishes, rather than saying
    # it can't read the type.
    def boots?
      yield
      true
    rescue Skyward::Core::BootError
      false
    end

    # The gems that read the type, as a body and as a column.
    def readers(type, signatures)
      FileUtils.mkdir_p(signatures)
      File.write(File.join(signatures, "probes.rbs"), <<~RBS)
        module TypesFixtures
          class Column < ::Skyward::ORM::Record
            attr_reader value: #{type}
          end

          class Body < ::Skyward::API
            def echo: (body: #{type}) -> (#{type})
          end

          class Item
            attr_reader id: Integer
          end

          class Tag
            attr_reader name: String
          end
        end
      RBS
      api = boots? { Skyward.app(signatures:, logger: nil) { |builder| builder.mount TypesFixtures::Body.new } }
      orm = boots? do
        Skyward.connect("sqlite://:memory:", signatures:, check: false).column_types.columns(TypesFixtures::Column)
      end
      { api:, orm: }.select { |_, reads| reads }.keys
    end

    it "are only the ones listed" do
      read = candidates.each_with_index.to_h { |type, index| [type, readers(type, File.join(directory, index.to_s))] }

      assert_equal(known, read.reject { |_, gems| gems == %i[api orm] })
    end
  end
end
