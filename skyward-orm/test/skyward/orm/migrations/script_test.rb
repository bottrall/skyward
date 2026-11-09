# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../../fixtures/migrations/migrations_fixtures"
require_relative "../../../fixtures/migrations/postgres"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Migrations::Script do
  fixtures = MigrationsFixtures
  migrations = Skyward::ORM::Migrations
  sqlite = Skyward::ORM::Adapters::SQLite
  postgres = MigrationsFixtures::Postgres
  readers = %w[migrations tables].to_h do |name|
    signatures = File.expand_path("../../../fixtures/#{name}/sig", __dir__)
    [name, Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))]
  end

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("migrations")) }

  def create(klass) = Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))

  def add(klass, *names)
    columns = column_types.columns(klass).select { |column| names.include?(column.name) }
    Skyward::ORM::Migrations::AddColumns.new(klass:, columns:)
  end

  def write(changes, adapter = Skyward::ORM::Adapters::SQLite)
    Skyward::ORM::Migrations::Script.write(changes, adapter)
  end

  describe ".write" do
    it "writes the README's create_todos for PostgreSQL" do
      readme = File.read(File.expand_path("../../../../README.md", __dir__))
      example = readme[%r{^-- db/migrate/\d+_create_todos\.sql\n(.*?)^```}m, 1]
      todo = TablesFixtures::Todo
      columns = Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("tables")).columns(todo)

      assert_equal example, write([migrations::CreateTable.new(klass: todo, columns:)], postgres)
    end

    it "writes the README's Todo for SQLite, in SQLite's types" do
      expected = <<~SQL
        CREATE TABLE todos (
          id          INTEGER CONSTRAINT todos_pkey PRIMARY KEY,
          list_id     INTEGER NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE CASCADE,
          title       TEXT    NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200),
          priority    TEXT    NOT NULL DEFAULT 'normal' CONSTRAINT todos_priority_check CHECK (priority IN ('low', 'normal', 'high')),
          due_on      TEXT,
          done        INTEGER NOT NULL DEFAULT 0,
          created_at  TEXT    NOT NULL DEFAULT (CURRENT_TIMESTAMP)
        );
        CREATE INDEX todos_list_id_done_index ON todos (list_id, done);

        -- down
        DROP TABLE todos;
      SQL

      assert_equal expected, write([create(fixtures::Todo)])
    end

    it "writes every other declaration, naming each constraint" do
      expected = <<~SQL
        CREATE TABLE members (
          email         TEXT    NOT NULL CONSTRAINT members_pkey PRIMARY KEY,
          list_id       INTEGER CONSTRAINT members_list_id_fkey REFERENCES lists ON DELETE SET NULL,
          mentor_email  TEXT    CONSTRAINT members_mentor_email_fkey REFERENCES members,
          handle        TEXT    NOT NULL CONSTRAINT members_handle_key UNIQUE CONSTRAINT members_handle_check CHECK (length(handle) >= 3) CONSTRAINT members_handle_check1 CHECK (handle = lower(handle)),
          nickname      TEXT    NOT NULL DEFAULT 'it''s me' CONSTRAINT members_nickname_check CHECK (length(nickname) <= 20),
          score         REAL    NOT NULL DEFAULT 1.5,
          joined_on     TEXT    NOT NULL DEFAULT '2026-10-18',
          role          TEXT    CONSTRAINT members_role_check CHECK (role IN ('admin', 'member')),
          note          TEXT    DEFAULT NULL,
          CONSTRAINT members_list_id_handle_key UNIQUE (list_id, handle)
        );

        -- down
        DROP TABLE members;
      SQL

      assert_equal expected, write([create(fixtures::Member)])
    end

    it "quotes a default its adapter passes through as its text" do
      assert_match(/^  joined_on +date +NOT NULL DEFAULT '2026-10-18',$/, write([create(fixtures::Member)], postgres))
    end

    it "leaves a column with no type for you to write, with no comma after the column before it" do
      expected = <<~SQL
        CREATE TABLE scraps (
          id       INTEGER CONSTRAINT scraps_pkey PRIMARY KEY
          -- TODO: scraps.payload needs a type
        );

        -- down
        DROP TABLE scraps;
      SQL

      assert_equal expected, write([create(fixtures::Scrap)])
    end

    it "adds columns, asking for a type, or a default for a required column with none" do
      expected = <<~SQL
        ALTER TABLE todos ADD COLUMN notes TEXT;
        ALTER TABLE todos ADD COLUMN rank INTEGER NOT NULL DEFAULT 0;
        -- TODO: todos.code needs a DEFAULT for the rows todos already has
        ALTER TABLE todos ADD COLUMN code TEXT NOT NULL;
        -- TODO: todos.extra needs a type

        -- down
        ALTER TABLE todos DROP COLUMN extra;
        ALTER TABLE todos DROP COLUMN code;
        ALTER TABLE todos DROP COLUMN rank;
        ALTER TABLE todos DROP COLUMN notes;
      SQL

      assert_equal expected, write([add(fixtures::NotedTodo, :notes, :rank, :code, :extra)])
    end

    it "separates each change with a blank line, and reverses them in the down section" do
      expected = <<~SQL
        CREATE TABLE lists (
          id    INTEGER CONSTRAINT lists_pkey PRIMARY KEY,
          name  TEXT    NOT NULL
        );

        ALTER TABLE todos ADD COLUMN notes TEXT;

        -- down
        ALTER TABLE todos DROP COLUMN notes;
        DROP TABLE lists;
      SQL

      assert_equal expected, write([create(fixtures::List), add(fixtures::NotedTodo, :notes)])
    end

    describe "on SQLite" do
      let(:connection) { sqlite.connect(":memory:") }

      def migrate(changes, section)
        connection.execute_batch(write(changes).split("-- down\n").fetch(section == :up ? 0 : 1))
      end

      it "runs up, to match each class, and down, to undo it" do
        created = [fixtures::List, fixtures::Todo, fixtures::Attachment, fixtures::Member].map { |klass| create(klass) }
        added = [add(fixtures::NotedTodo, :notes, :rank)]
        migrate(created, :up)
        migrate(added, :up)
        todos = sqlite.tables(connection).find { |table| table.name == :todos }
        notes = todos&.columns.to_a.map(&:name).last(2)
        migrate(added, :down)
        migrate(created, :down)

        assert_equal [%i[notes rank], []], [notes, sqlite.tables(connection)]
      end

      def violation(sql)
        connection.execute(sql)
      rescue SQLite3::ConstraintException => e
        Skyward::ORM::Adapters::SQLite.violation(e, Skyward::ORM::Adapters::SQLite.tables(connection), :todos)
      end

      it "names a check, so its violation names it" do
        migrate([create(fixtures::List), create(fixtures::Todo)], :up)
        connection.execute("INSERT INTO lists (name) VALUES ('Home')")
        found = violation("INSERT INTO todos (list_id, title) VALUES (1, '')")

        assert_equal ["todos_title_check", [:title]], [found&.constraint, found&.columns]
      end
    end
  end
end
