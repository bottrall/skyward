# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/migrations/migrations_fixtures"

describe Skyward::ORM::Migrations::Definitions do
  fixtures = MigrationsFixtures
  definitions = Skyward::ORM::Migrations::Definitions
  signatures = File.expand_path("../../../fixtures/migrations/sig", __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }

  def column(klass, name) = column_types.columns(klass).find { |column| column.name == name }

  def constraint(name, kind, columns, definition, references = nil)
    Skyward::ORM::Catalog::Constraint.new(name:, kind:, columns:, references:, definition:)
  end

  describe ".constraints" do
    it "names each constraint, column by column as each lists them, then the uniques on more than one column" do
      expected = [
        constraint("members_pkey", :primary_key, [:email], "PRIMARY KEY (email)"),
        constraint(
          "members_list_id_fkey",
          :foreign_key,
          [:list_id],
          "FOREIGN KEY (list_id) REFERENCES lists ON DELETE SET NULL",
          :lists
        ),
        constraint(
          "members_mentor_email_fkey",
          :foreign_key,
          [:mentor_email],
          "FOREIGN KEY (mentor_email) REFERENCES members",
          :members
        ),
        constraint("members_handle_key", :unique, [:handle], "UNIQUE (handle)"),
        constraint("members_handle_check", :check, [:handle], "CHECK (length(handle) >= 3)"),
        constraint("members_handle_check1", :check, [:handle], "CHECK (handle = lower(handle))"),
        constraint("members_nickname_check", :check, [:nickname], "CHECK (length(nickname) <= 20)"),
        constraint("members_role_check", :check, [:role], "CHECK (role IN ('admin', 'member'))"),
        constraint("members_list_id_handle_key", :unique, %i[list_id handle], "UNIQUE (list_id, handle)")
      ]

      assert_equal expected, definitions.constraints(fixtures::Member, column_types.columns(fixtures::Member))
    end

    it "writes a length with both bounds as BETWEEN" do
      found = definitions.constraints(fixtures::Todo, column_types.columns(fixtures::Todo)).find do |had|
        had.kind == :check
      end

      assert_equal "CHECK (length(title) BETWEEN 1 AND 200)", found&.definition
    end
  end

  describe ".indexes" do
    it "names each index after its table and columns" do
      expected = Skyward::ORM::Catalog::Index.new(
        name: "todos_list_id_done_index",
        columns: %i[list_id done],
        unique: false,
        definition: "CREATE INDEX todos_list_id_done_index ON todos (list_id, done)"
      )

      assert_equal [expected], definitions.indexes(fixtures::Todo)
    end
  end

  describe ".default" do
    it "writes a value as its adapter stores it, an expression as its adapter writes one, and nil for none" do
      found = [
        definitions.default(fixtures::Todo, column(fixtures::Todo, :done), Skyward::ORM::Adapters::SQLite),
        definitions.default(fixtures::Todo, column(fixtures::Todo, :created_at), Skyward::ORM::Adapters::SQLite),
        definitions.default(fixtures::Todo, column(fixtures::Todo, :created_at), Skyward::ORM::Adapters::PostgreSQL),
        definitions.default(fixtures::Todo, column(fixtures::Todo, :title), Skyward::ORM::Adapters::SQLite)
      ]

      assert_equal ["0", "(CURRENT_TIMESTAMP)", "CURRENT_TIMESTAMP", nil], found
    end

    it "writes a JSON column's default as JSON" do
      settings = column(fixtures::Webhook, :settings)

      assert_equal %('{"retries":3,"it''s":[1.5,null,{"on":true}],"ü":""}'),
                   definitions.default(fixtures::Webhook, settings, Skyward::ORM::Adapters::PostgreSQL)
    end
  end

  describe ".inline" do
    it "writes a constraint as a column's own" do
      found = definitions.constraints(fixtures::Member, column_types.columns(fixtures::Member)).first(4)

      assert_equal(
        [
          "CONSTRAINT members_pkey PRIMARY KEY",
          "CONSTRAINT members_list_id_fkey REFERENCES lists ON DELETE SET NULL",
          "CONSTRAINT members_mentor_email_fkey REFERENCES members",
          "CONSTRAINT members_handle_key UNIQUE"
        ],
        found.map { |had| definitions.inline(had) }
      )
    end
  end

  describe ".literal" do
    it "writes NULL, a quoted string, a number or boolean as it is, and anything else as its text" do
      assert_equal(
        ["NULL", "'it''s'", "1.5", "true", "'2026-10-18'"],
        [nil, "it's", 1.5, true, Date.new(2026, 10, 18)].map { |value| definitions.literal(value) }
      )
    end
  end
end
