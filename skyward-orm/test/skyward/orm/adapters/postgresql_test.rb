# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Adapters::PostgreSQL do
  postgresql = Skyward::ORM::Adapters::PostgreSQL
  catalog = Skyward::ORM::Catalog

  schema = [
    <<~SQL,
      CREATE TABLE lists (
        id bigint CONSTRAINT lists_pkey PRIMARY KEY,
        name text NOT NULL CONSTRAINT lists_name_key UNIQUE,
        slug varchar(40)
      )
    SQL
    "CREATE UNIQUE INDEX lists_slug_index ON lists (lower(slug))",
    <<~SQL,
      CREATE TABLE todos (
        id bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT todos_pkey PRIMARY KEY,
        list_id bigint NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE RESTRICT,
        title text NOT NULL CONSTRAINT todos_title_check CHECK (length(title) > 0),
        due_at timestamp(3) with time zone,
        code text,
        CONSTRAINT todos_open_check CHECK (true)
      )
    SQL
    "CREATE UNIQUE INDEX todos_code_index ON todos (code)",
    "CREATE INDEX todos_list_id_title_index ON todos (list_id, title) INCLUDE (code)",
    "INSERT INTO lists (id, name, slug) VALUES (1, 'Home', 'home')",
    "INSERT INTO todos (list_id, title, code) VALUES (1, 'Buy milk', 'milk')"
  ]

  let(:empty) { TestDatabase.empty("postgresql") }
  let(:connection) { empty.connect.tap { |connection| schema.each { |sql| connection.execute(sql) } } }
  let(:tables) { postgresql.tables(connection) }

  def violation(sql, tables = self.tables)
    connection.execute(sql)
  rescue StandardError => e
    Skyward::ORM::Adapters::PostgreSQL.violation(e, tables, :todos)
  end

  def violation_of(kind, constraint, columns, message)
    Skyward::ORM::Violation.new(kind:, constraint:, columns:, message:)
  end

  describe ".driver" do
    it "is the pg gem" do
      assert_equal "pg", postgresql.driver
    end
  end

  describe ".adapter_name" do
    it "is :postgresql" do
      assert_equal :postgresql, postgresql.adapter_name
    end
  end

  describe ".connect" do
    it "sets the session to UTC, with dates written as ISO 8601, and only warnings and worse sent" do
      settings = %w[TimeZone DateStyle client_min_messages].map { |name| "current_setting('#{name}')" }.join(", ")

      assert_equal [["UTC", "ISO, MDY", "warning"]], empty.connect.execute("SELECT #{settings}")
    end
  end

  describe ".pool_size" do
    it "keeps the size asked for" do
      assert_equal 5, postgresql.pool_size("localhost/todos", 5)
    end
  end

  describe ".placeholder" do
    it "numbers each position" do
      assert_equal "$2", postgresql.placeholder(2)
    end
  end

  describe ".bind_limit" do
    it "is the most parameters the protocol counts" do
      assert_equal 65_535, postgresql.bind_limit
    end
  end

  describe ".unlimited" do
    it "is nothing, since an OFFSET needs no LIMIT before it" do
      assert_nil postgresql.unlimited
    end
  end

  describe ".sql_type" do
    it "maps each column type to the README's PostgreSQL type" do
      types = %i[integer float decimal string bool date time enum uuid int32 int16 json].to_h do |type|
        [type, postgresql.sql_type(type)]
      end

      assert_equal(
        { integer: "bigint", float: "double precision", decimal: "numeric", string: "text", bool: "boolean",
          date: "date", time: "timestamptz", enum: "text", uuid: "uuid", int32: "integer", int16: "smallint",
          json: "jsonb" },
        types
      )
    end

    it "has none for an untyped column" do
      assert_nil postgresql.sql_type(:untyped)
    end
  end

  describe ".identity" do
    it "is a clause that numbers an integer primary key" do
      connection.execute("CREATE TABLE counters (id bigint #{postgresql.identity} PRIMARY KEY, name text)")

      assert_equal [["1"]], connection.execute("INSERT INTO counters (name) VALUES ('a') RETURNING id")
    end
  end

  describe ".alters_in_place?" do
    it "is true, since ALTER TABLE can change any column or constraint" do
      assert_predicate postgresql, :alters_in_place?
    end
  end

  describe ".begin_migration" do
    it "begins a transaction holding a lock no other connection can take until it ends" do
      migrating = empty.connect
      other = empty.connect
      take = "SELECT pg_try_advisory_xact_lock(#{postgresql::MIGRATION_LOCK})"
      migrating.execute_batch(postgresql.begin_migration)
      held = other.execute(take)
      migrating.execute("COMMIT")

      assert_equal [[["f"]], [["t"]]], [held, other.execute(take)]
    end
  end

  describe ".foreign_key_violations" do
    it "has none, since PostgreSQL checks each foreign key as it writes" do
      assert_empty postgresql.foreign_key_violations(connection)
    end
  end

  describe ".end_migration" do
    it "is nothing, since ending the transaction releases the lock" do
      assert_nil postgresql.end_migration
    end
  end

  describe ".default_expression" do
    it "is the expression as it's written" do
      connection.execute("CREATE TABLE stamps (at date DEFAULT #{postgresql.default_expression("current_date")})")
      connection.execute("INSERT INTO stamps DEFAULT VALUES")

      assert_equal [["t"]], connection.execute("SELECT at = current_date FROM stamps")
    end
  end

  describe ".compatible?" do
    it "accepts any declared type for an untyped column" do
      assert postgresql.compatible?(:untyped, "bytea")
    end

    it "accepts the type a migration writes, as the catalog spells it" do
      declared = [
        [:integer, "bigint"],
        [:float, "double precision"],
        [:decimal, "numeric"],
        [:string, "text"],
        [:bool, "boolean"],
        [:date, "date"],
        [:time, "timestamp with time zone"],
        [:enum, "text"],
        [:uuid, "uuid"],
        [:int32, "integer"],
        [:int16, "smallint"],
        [:json, "jsonb"]
      ]

      assert(declared.all? { |type, sql_type| postgresql.compatible?(type, sql_type) })
    end

    it "accepts integer, smallint, varchar, timestamp and numeric, with or without a length or precision" do
      declared = [
        [:decimal, "numeric(10,2)"],
        [:integer, "integer"],
        [:integer, "smallint"],
        [:string, "character varying(255)"],
        [:string, "character varying"],
        [:enum, "character varying(10)"],
        [:time, "timestamp without time zone"],
        [:time, "timestamp(3) with time zone"]
      ]

      assert(declared.all? { |type, sql_type| postgresql.compatible?(type, sql_type) })
    end

    it "accepts uuid and citext for a string, real for a float, and json for a JSON column" do
      declared = [[:string, "uuid"], [:string, "citext"], [:float, "real"], [:json, "json"]]

      assert(declared.all? { |type, sql_type| postgresql.compatible?(type, sql_type) })
    end

    it "refuses any other type" do
      declared = [[:integer, "text"], [:float, "numeric(10,2)"], [:string, "bytea"], [:bool, "integer"],
                  [:date, "timestamp with time zone"], [:time, "date"], [:enum, "integer"], [:uuid, "text"],
                  [:int32, "bigint"], [:int16, "integer"], [:json, "text"], [:decimal, "double precision"]]

      assert(declared.none? { |type, sql_type| postgresql.compatible?(type, sql_type) })
    end
  end

  describe ".comparable" do
    it "compares every column as it is, a numeric included" do
      assert_equal ['"price"', '"title"'],
                   [postgresql.comparable(:decimal, '"price"'), postgresql.comparable(:string, '"title"')]
    end
  end

  describe ".column_type" do
    it "reads each type compatible? accepts as the narrowest column type, without its length or precision" do
      read = ["bigint", "integer", "smallint", "double precision", "real", "numeric(10,2)", "text",
              "character varying(255)", "citext", "uuid", "boolean", "date", "timestamp(3) with time zone",
              "timestamp without time zone"]

      assert_equal(
        %i[integer int32 int16 float float decimal string string string uuid bool date time time],
        read.map { |sql_type| postgresql.column_type(sql_type) }
      )
    end

    it "returns only a type compatible? accepts for the same SQL type" do
      read = postgresql::COLUMN_TYPES.keys

      assert(read.all? { |sql_type| postgresql.compatible?(postgresql.column_type(sql_type), sql_type) })
    end

    it "has none for any other type" do
      read = ["jsonb", "bytea", "text[]"]

      assert_equal([nil] * 3, read.map { |sql_type| postgresql.column_type(sql_type) })
    end
  end

  describe ".encode" do
    it "sends a symbol as its name" do
      assert_equal "high", postgresql.encode(:high)
    end

    it "sends a time as UTC text, to the microsecond" do
      assert_equal "2026-10-18 09:30:00.123456+00",
                   postgresql.encode(Time.new(2026, 10, 18, 19, 30, 123_456_789/1_000_000_000r, "+10:00"))
    end

    it "leaves off a time's trailing zeros, as PostgreSQL writes it back" do
      assert_equal ["2026-10-18 09:30:00.5+00", "2026-10-18 09:30:00+00"],
                   [postgresql.encode(Time.utc(2026, 10, 18, 9, 30, 1/2r)),
                    postgresql.encode(Time.utc(2026, 10, 18, 9, 30))]
    end

    it "sends a BigDecimal as its digits, without an exponent" do
      assert_equal(%w[1.5 2.0 -0.0000001], %w[1.5 2 -1e-7].map { |text| postgresql.encode(BigDecimal(text)) })
    end

    it "sends a negative zero as 0.0" do
      assert_equal "0.0", postgresql.encode(BigDecimal("-0"))
    end

    it "passes anything else through, for the driver to send as text" do
      values = [true, 1, 1.5, "Milk", Date.new(2026, 10, 18)]

      assert_equal(values, values.map { |value| postgresql.encode(value) })
    end
  end

  describe ".decode" do
    it "reads an integer" do
      assert_equal 42, postgresql.decode(:integer, "42")
    end

    it "reads an int32 and an int16 as Integers" do
      assert_equal [2_147_483_647, -32_768],
                   [postgresql.decode(:int32, "2147483647"), postgresql.decode(:int16, "-32768")]
    end

    it "reads a float" do
      assert_in_delta 1.5, postgresql.decode(:float, "1.5")
    end

    it "reads the special floats PostgreSQL writes out" do
      assert_equal [Float::INFINITY, -Float::INFINITY, true],
                   [postgresql.decode(:float, "Infinity"), postgresql.decode(:float, "-Infinity"),
                    postgresql.decode(:float, "NaN").nan?]
    end

    it "reads t as true" do
      assert postgresql.decode(:bool, "t")
    end

    it "reads f as false" do
      refute postgresql.decode(:bool, "f")
    end

    it "reads a date" do
      assert_equal Date.new(2026, 10, 18), postgresql.decode(:date, "2026-10-18")
    end

    it "reads a timestamptz in UTC" do
      time = postgresql.decode(:time, "2026-10-18 19:30:00.123456+10")

      assert_equal [Time.utc(2026, 10, 18, 9, 30, 123_456/1_000_000r), true], [time, time.utc?]
    end

    it "reads a timestamp, which has no zone, as UTC" do
      assert_equal Time.utc(2026, 10, 18, 9, 30), postgresql.decode(:time, "2026-10-18 09:30:00")
    end

    it "reads a symbol" do
      assert_equal :high, postgresql.decode(:enum, "high")
    end

    it "reads a numeric's text as a BigDecimal, with every digit" do
      assert_equal BigDecimal("12345678901234567890.123456789"),
                   postgresql.decode(:decimal, "12345678901234567890.123456789")
    end

    it "reads JSON into a Hash, frozen at every level" do
      read = postgresql.decode(:json, +'{"list": [{"deep": "ü"}]}')

      assert_equal [{ "list" => [{ "deep" => "ü" }] }, true],
                   [read, [read, read["list"], read["list"][0], read["list"][0]["deep"]].all?(&:frozen?)]
    end

    it "freezes a string" do
      assert_predicate postgresql.decode(:string, +"Milk"), :frozen?
    end

    it "passes an untyped value through, frozen" do
      assert_predicate postgresql.decode(:untyped, +"Milk"), :frozen?
    end

    it "reads back what was written: a time == to it at microsecond precision, a date, a boolean and a symbol" do
      connection.execute("CREATE TABLE values (at timestamptz, local timestamp, on_day date, done boolean, level text)")
      time = Time.new(2026, 10, 18, 19, 30, 123_456_789/1_000_000_000r, "+10:00")
      written = [time, time, Date.new(2026, 10, 18), false, :high]
      connection.execute(
        "INSERT INTO values VALUES ($1, $2, $3, $4, $5)",
        written.map { |value| postgresql.encode(value) }
      )
      types = %i[time time date bool enum]
      read = connection.execute("SELECT * FROM values").fetch(0).zip(types).map do |value, type|
        postgresql.decode(type, value)
      end

      assert_equal [time.floor(6), time.floor(6), *written.drop(2)], read
    end

    it "reads back what was written to a numeric column, with every digit" do
      connection.execute("CREATE TABLE prices (price numeric)")
      written = BigDecimal("12345678901234567890.123456789")
      connection.execute("INSERT INTO prices VALUES ($1)", [postgresql.encode(written)])

      assert_equal written, postgresql.decode(:decimal, connection.execute("SELECT price FROM prices").dig(0, 0))
    end

    it "reads back what was written to a uuid, an integer and a smallint column, as a String and Integers" do
      connection.execute("CREATE TABLE refined (id uuid, logins integer, rank smallint)")
      written = ["0b9d5f2e-7c4a-4e1b-9f3d-2a6c8e0b1d4f", 2_147_483_647, -32_768]
      connection.execute("INSERT INTO refined VALUES ($1, $2, $3)", written.map { |value| postgresql.encode(value) })
      read = connection.execute("SELECT * FROM refined").fetch(0).zip(%i[uuid int32 int16]).map do |value, type|
        postgresql.decode(type, value)
      end

      assert_equal written, read
    end
  end

  describe ".tables" do
    def table(name) = tables.find { |table| table.name == name }

    it "reads each column's type and nullability, and no default for an identity column" do
      expected = [
        catalog::Column.new(name: :id, type: "bigint", nullable: false, default: nil, generated: nil),
        catalog::Column.new(name: :list_id, type: "bigint", nullable: false, default: nil, generated: nil),
        catalog::Column.new(name: :title, type: "text", nullable: false, default: nil, generated: nil),
        catalog::Column.new(
          name: :due_at,
          type: "timestamp(3) with time zone",
          nullable: true,
          default: nil,
          generated: nil
        ),
        catalog::Column.new(name: :code, type: "text", nullable: true, default: nil, generated: nil)
      ]

      assert_equal expected, table(:todos).columns
    end

    it "reads a generated column's expression, and no default, which PostgreSQL keeps as its default" do
      connection.execute("CREATE TABLE searches (title text, search text GENERATED ALWAYS AS (lower(title)) STORED)")
      expected = catalog::Column.new(
        name: :search, type: "text", nullable: true, default: nil, generated: "lower(title)"
      )

      assert_equal expected, table(:searches).columns.fetch(1)
    end

    it "reads each default as a migration writes it, without the cast PostgreSQL reads a literal back with" do
      time = postgresql.encode(Time.utc(2026, 10, 18, 9, 30, 1/2r))
      connection.execute(<<~SQL)
        CREATE TABLE defaults (
          a text DEFAULT 'it''s me', b boolean DEFAULT false, c bigint DEFAULT -1, d bigint DEFAULT 3000000000,
          e double precision DEFAULT -1.5, f date DEFAULT '2026-10-18', g timestamptz DEFAULT '#{time}',
          h timestamptz DEFAULT now()
        )
      SQL
      expected = ["'it''s me'", "false", "-1", "3000000000", "-1.5", "'2026-10-18'", "'#{time}'", "now()"]

      assert_equal expected, table(:defaults).columns.map(&:default)
    end

    it "reads each index's key columns, but not the indexes its constraints make" do
      expected = [
        catalog::Index.new(
          name: "todos_code_index",
          columns: [:code],
          unique: true,
          definition: "CREATE UNIQUE INDEX todos_code_index ON public.todos USING btree (code)"
        ),
        catalog::Index.new(
          name: "todos_list_id_title_index",
          columns: %i[list_id title],
          unique: false,
          definition: "CREATE INDEX todos_list_id_title_index ON public.todos USING btree (list_id, title) " \
                      "INCLUDE (code)"
        )
      ]

      assert_equal expected, table(:todos).indexes
    end

    it "reads an index on an expression as having no columns" do
      expected = catalog::Index.new(
        name: "lists_slug_index",
        columns: [],
        unique: true,
        definition: "CREATE UNIQUE INDEX lists_slug_index ON public.lists USING btree (lower((slug)::text))"
      )

      assert_equal [expected], table(:lists).indexes
    end

    it "reads each constraint by name, with its columns and its definition as a table constraint" do
      expected = [
        catalog::Constraint.new(
          name: "todos_list_id_fkey",
          kind: :foreign_key,
          columns: [:list_id],
          references: :lists,
          definition: "FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE RESTRICT"
        ),
        catalog::Constraint.new(
          name: "todos_open_check", kind: :check, columns: [], references: nil, definition: "CHECK (true)"
        ),
        catalog::Constraint.new(
          name: "todos_pkey", kind: :primary_key, columns: [:id], references: nil, definition: "PRIMARY KEY (id)"
        ),
        catalog::Constraint.new(
          name: "todos_title_check",
          kind: :check,
          columns: [:title],
          references: nil,
          definition: "CHECK ((length(title) > 0))"
        )
      ]

      assert_equal expected, table(:todos).constraints
    end

    it "reads only the tables an unqualified name finds, and a table with no indexes or constraints" do
      connection = empty.connect
      connection.execute("CREATE SCHEMA elsewhere")
      connection.execute("CREATE TABLE elsewhere.hidden (id bigint)")
      connection.execute("CREATE TABLE notes (body text)")

      assert_equal(
        [[:notes, [], []]],
        postgresql.tables(connection).map do |table|
          [table.name, table.indexes, table.constraints]
        end
      )
    ensure
      connection&.execute("DROP TABLE IF EXISTS elsewhere.hidden")
      connection&.execute("DROP SCHEMA IF EXISTS elsewhere")
    end
  end

  describe ".violation" do
    unique = 'duplicate key value violates unique constraint "%s"'

    it "is nil for an error that isn't the database's" do
      assert_nil postgresql.violation(StandardError.new("failed"), tables, :todos)
    end

    it "is nil for an error that isn't a violation" do
      assert_nil violation("SELECT * FROM missing")
    end

    it "names a unique constraint, with its columns" do
      expected = violation_of(:unique, "lists_name_key", [:name], format(unique, "lists_name_key"))

      assert_equal expected, violation("INSERT INTO lists (id, name) VALUES (2, 'Home')")
    end

    it "names a primary key" do
      expected = violation_of(:unique, "lists_pkey", [:id], format(unique, "lists_pkey"))

      assert_equal expected, violation("INSERT INTO lists (id, name) VALUES (1, 'Work')")
    end

    it "names a unique index, with its columns" do
      expected = violation_of(:unique, "todos_code_index", [:code], format(unique, "todos_code_index"))

      assert_equal expected, violation("INSERT INTO todos (list_id, title, code) VALUES (1, 'Eggs', 'milk')")
    end

    it "names a unique index on an expression, which has no columns" do
      expected = violation_of(:unique, "lists_slug_index", [], format(unique, "lists_slug_index"))

      assert_equal expected, violation("INSERT INTO lists (id, name, slug) VALUES (2, 'Work', 'HOME')")
    end

    it "names a foreign key on the table written" do
      message = 'insert or update on table "todos" violates foreign key constraint "todos_list_id_fkey"'
      expected = violation_of(:foreign_key, "todos_list_id_fkey", [:list_id], message)

      assert_equal expected, violation("INSERT INTO todos (list_id, title) VALUES (9, 'Eggs')")
    end

    it "names a foreign key that refers to the table written, from the table that has it" do
      message = 'update or delete on table "lists" violates foreign key constraint "todos_list_id_fkey" ' \
                'on table "todos"'
      expected = violation_of(:foreign_key, "todos_list_id_fkey", [:list_id], message)

      assert_equal expected, violation("DELETE FROM lists")
    end

    it "reads a not-null violation's column" do
      message = 'null value in column "name" of relation "lists" violates not-null constraint'

      assert_equal violation_of(:not_null, nil, [:name], message),
                   violation("INSERT INTO lists (id, name) VALUES (2, NULL)")
    end

    it "names a check, with its columns" do
      message = 'new row for relation "todos" violates check constraint "todos_title_check"'

      assert_equal violation_of(:check, "todos_title_check", [:title], message),
                   violation("INSERT INTO todos (list_id, title) VALUES (1, '')")
    end

    it "has no columns for a constraint the schema it was given doesn't have" do
      expected = violation_of(:unique, "lists_name_key", [], format(unique, "lists_name_key"))

      assert_equal expected, violation("INSERT INTO lists (id, name) VALUES (2, 'Home')", [])
    end
  end
end
