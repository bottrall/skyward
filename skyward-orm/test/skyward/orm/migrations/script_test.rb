# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../../fixtures/migrations/migrations_fixtures"
require_relative "../../../fixtures/tables/tables_fixtures"
require_relative "../../../fixtures/changes/changes_fixtures"

describe Skyward::ORM::Migrations::Script do
  fixtures = MigrationsFixtures
  changed = ChangesFixtures
  migrations = Skyward::ORM::Migrations
  catalog = Skyward::ORM::Catalog
  sqlite = Skyward::ORM::Adapters::SQLite
  postgres = Skyward::ORM::Adapters::PostgreSQL
  readers = %w[migrations tables changes].to_h do |name|
    signatures = File.expand_path("../../../fixtures/#{name}/sig", __dir__)
    builder = Skyward::Core::Signatures.load(signatures)
    [name, Skyward::Core::Types::Reader.new(builder, refinements: Skyward::ORM::Tables::ColumnTypes::REFINEMENTS)]
  end

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("migrations")) }
  let(:changes_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("changes")) }

  def create(klass) = Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))

  def alter(klass, edits, table: catalog_table(klass.table_name), types: column_types)
    Skyward::ORM::Migrations::AlterTable.new(
      klass:, columns: types.columns(klass), table:, edits:, kept_indexes: [], kept_constraints: []
    )
  end

  def add(klass, *names)
    columns = column_types.columns(klass).select { |column| names.include?(column.name) }
    alter(klass, columns.map { |column| Skyward::ORM::Migrations::AddColumn.new(column:) })
  end

  def catalog_table(name, columns = [], constraints: [], indexes: [])
    Skyward::ORM::Catalog::Table.new(name:, columns:, indexes:, constraints:)
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

    it "numbers an int32 or int16 primary key, and gives a uuid one its default, in PostgreSQL's types" do
      expected = <<~SQL
        CREATE TABLE counters (
          id    integer GENERATED ALWAYS AS IDENTITY CONSTRAINT counters_pkey PRIMARY KEY,
          hits  smallint NOT NULL
        );

        CREATE TABLE tallies (
          id  smallint GENERATED ALWAYS AS IDENTITY CONSTRAINT tallies_pkey PRIMARY KEY
        );

        CREATE TABLE visits (
          id          uuid NOT NULL DEFAULT gen_random_uuid() CONSTRAINT visits_pkey PRIMARY KEY,
          invited_by  uuid
        );

        -- down
        DROP TABLE visits;
        DROP TABLE tallies;
        DROP TABLE counters;
      SQL

      created = [fixtures::Counter, fixtures::Tally, fixtures::Visit].map { |klass| create(klass) }

      assert_equal expected, write(created, postgres)
    end

    it "writes them in SQLite's types, where an INTEGER PRIMARY KEY numbers its rows" do
      expected = <<~SQL
        CREATE TABLE counters (
          id    INTEGER CONSTRAINT counters_pkey PRIMARY KEY,
          hits  INTEGER NOT NULL
        );

        CREATE TABLE tallies (
          id  INTEGER CONSTRAINT tallies_pkey PRIMARY KEY
        );

        CREATE TABLE visits (
          id          TEXT NOT NULL DEFAULT (gen_random_uuid()) CONSTRAINT visits_pkey PRIMARY KEY,
          invited_by  TEXT
        );

        -- down
        DROP TABLE visits;
        DROP TABLE tallies;
        DROP TABLE counters;
      SQL

      created = [fixtures::Counter, fixtures::Tally, fixtures::Visit].map { |klass| create(klass) }

      assert_equal expected, write(created)
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

    it "writes the README's rework_todos for PostgreSQL" do
      readme = File.read(File.expand_path("../../../../README.md", __dir__))
      example = readme[%r{^-- db/migrate/\d+_rework_todos\.sql\n(.*?)^```}m, 1]

      assert_equal example, write([alter(fixtures::Todo, MigrationsFixtures.rework_todos)], postgres)
    end

    describe "where a database alters a table in place, as PostgreSQL does" do
      note = catalog::Column.new(name: :note, type: "text", nullable: false, default: "'none'")
      check = catalog::Constraint.new(
        name: "todos_title_check", kind: :check, columns: [:title], references: nil, definition: "CHECK (title <> '')"
      )
      index = catalog::Index.new(
        name: "todos_done_index",
        columns: [:done],
        unique: false,
        definition: "CREATE INDEX todos_done_index ON todos (done)"
      )

      it "makes each change with ALTER TABLE, undoing them in reverse" do
        edits = [
          migrations::DropIndex.new(index:),
          migrations::DropConstraint.new(constraint: check),
          migrations::DropColumn.new(column: note),
          migrations::RenameColumn.new(from: :due, to: :due_on),
          migrations::ChangeType.new(column: :rank, from: "integer", to: "text"),
          migrations::ChangeDefault.new(column: :done, from: nil, to: "false"),
          migrations::ChangeNullable.new(column: :title, nullable: false),
          migrations::AddConstraint.new(constraint: check.with(name: "todos_title_check1")),
          migrations::AddIndex.new(index: index.with(name: "todos_done_index1"))
        ]
        expected = <<~SQL
          DROP INDEX todos_done_index;
          ALTER TABLE todos DROP CONSTRAINT todos_title_check;
          ALTER TABLE todos DROP COLUMN note;
          ALTER TABLE todos RENAME COLUMN due TO due_on;
          ALTER TABLE todos ALTER COLUMN rank TYPE text USING rank::text;
          ALTER TABLE todos ALTER COLUMN done SET DEFAULT false;
          -- TODO: backfill the NULLs in todos.title before it becomes NOT NULL
          ALTER TABLE todos ALTER COLUMN title SET NOT NULL;
          ALTER TABLE todos ADD CONSTRAINT todos_title_check1 CHECK (title <> '');
          CREATE INDEX todos_done_index ON todos (done);

          -- down
          DROP INDEX todos_done_index1;
          ALTER TABLE todos DROP CONSTRAINT todos_title_check1;
          ALTER TABLE todos ALTER COLUMN title DROP NOT NULL;
          ALTER TABLE todos ALTER COLUMN done DROP DEFAULT;
          ALTER TABLE todos ALTER COLUMN rank TYPE integer USING rank::integer;
          ALTER TABLE todos RENAME COLUMN due_on TO due;
          -- todos.note comes back empty: dropping it lost its data
          ALTER TABLE todos ADD COLUMN note text NOT NULL DEFAULT 'none';
          ALTER TABLE todos ADD CONSTRAINT todos_title_check CHECK (title <> '');
          CREATE INDEX todos_done_index ON todos (done);
        SQL

        assert_equal expected, write([alter(fixtures::Todo, edits)], postgres)
      end

      it "undoes making a column nullable by asking for its NULLs to be backfilled" do
        down = write(
          [alter(fixtures::Todo, [migrations::ChangeNullable.new(column: :title, nullable: true)])],
          postgres
        )

        assert_equal "ALTER TABLE todos ALTER COLUMN title DROP NOT NULL;\n\n-- down\n" \
                     "-- TODO: backfill the NULLs in todos.title before it becomes NOT NULL\n" \
                     "ALTER TABLE todos ALTER COLUMN title SET NOT NULL;\n",
                     down
      end

      it "asks for a default before it adds back a required column that had none" do
        dropped = migrations::DropColumn.new(column: note.with(default: nil))

        assert_equal "ALTER TABLE todos DROP COLUMN note;\n\n-- down\n" \
                     "-- todos.note comes back empty: dropping it lost its data\n" \
                     "-- TODO: todos.note needs a DEFAULT for the rows todos already has\n" \
                     "ALTER TABLE todos ADD COLUMN note text NOT NULL;\n",
                     write([alter(fixtures::Todo, [dropped])], postgres)
      end

      it "drops a default, and adds back one with no type and no name" do
        unnamed = check.with(name: nil)
        edits = [
          migrations::ChangeDefault.new(column: :done, from: "false", to: nil),
          migrations::DropColumn.new(column: note.with(type: "", nullable: true, default: nil)),
          migrations::DropConstraint.new(constraint: unnamed)
        ]

        assert_equal "ALTER TABLE todos ADD CHECK (title <> '');\n" \
                     "-- todos.note comes back empty: dropping it lost its data\n" \
                     "ALTER TABLE todos ADD COLUMN note;\n" \
                     "ALTER TABLE todos ALTER COLUMN done SET DEFAULT false;\n",
                     write([alter(fixtures::Todo, edits)], postgres).split("-- down\n").fetch(1)
      end
    end

    # What running a migration does on every database, so each runs these.
    running = proc do
      def section(changes, part) = write(changes, adapter).split("-- down\n").fetch(part == :up ? 0 : 1)

      def diff(classes)
        Skyward::ORM::Migrations::Diff.changes(
          classes,
          changes_types,
          adapter.tables(connection),
          adapter,
          lambda { |*|
            true
          }
        )
      end

      # Columns come back in another order once one is dropped and added back.
      def schema
        adapter.tables(connection).map do |table|
          table.with(
            columns: table.columns.sort_by(&:name),
            constraints: table.constraints.sort_by { |constraint| [constraint.name.to_s, constraint.definition] },
            indexes: table.indexes.sort_by(&:name)
          )
        end
      end

      def rows = connection.execute("SELECT owner_id, title, code FROM items")

      def items
        migrate(section(diff([ChangesFixtures::Owner, ChangesFixtures::Item]), :up))
        connection.execute("INSERT INTO owners (name) VALUES ('Ann')")
        connection.execute("INSERT INTO items (owner_id, title, code, note, rank) VALUES (1, 'Milk', 'milk', 'two', 2)")
      end

      def violation(sql)
        connection.execute(sql)
      rescue StandardError => e
        adapter.violation(e, adapter.tables(connection), :todos)
      end

      it "runs up, to match each class, and down, to undo it" do
        created = [fixtures::List, fixtures::Todo, fixtures::Attachment, fixtures::Member].map { |klass| create(klass) }
        added = [add(fixtures::NotedTodo, :notes, :rank)]
        migrate(section(created, :up))
        migrate(section(added, :up))
        todos = adapter.tables(connection).find { |table| table.name == :todos }
        notes = todos&.columns.to_a.map(&:name).last(2)
        migrate(section(added, :down))
        migrate(section(created, :down))

        assert_equal [%i[notes rank], []], [notes, adapter.tables(connection)]
      end

      it "names a check, so its violation names it" do
        migrate(section([create(fixtures::List), create(fixtures::Todo)], :up))
        connection.execute("INSERT INTO lists (name) VALUES ('Home')")
        found = violation("INSERT INTO todos (list_id, title) VALUES (1, '')")

        assert_equal ["todos_title_check", [:title]], [found&.constraint, found&.columns]
      end

      %i[
        Dropped Renamed Added Serialed Stamped Retyped Required Redefaulted
        Unchecked Checked Paired Reindexed Restricted
      ].each do |name|
        it "round-trips a class that's #{name}: the table matches it after up, and the table it had after down" do
          items
          had = schema
          kept = rows
          variant = changed.const_get(name)
          changes = diff([changed::Owner, variant])
          migrate(section(changes, :up))
          matched = [diff([changed::Owner, variant]), rows]
          migrate(section(changes, :down))

          assert_equal [[[], kept], had, []], [matched, schema, diff([changed::Owner, changed::Item])]
        end
      end

      it "keeps a renamed column's data" do
        items
        migrate(section(diff([changed::Owner, changed::Renamed]), :up))

        assert_equal [["two"]], connection.execute("SELECT remark FROM items")
      end

      it "numbers an int32 or int16 primary key" do
        migrate(section([create(fixtures::Counter), create(fixtures::Tally)], :up))
        ids = ["INSERT INTO counters (hits) VALUES (1) RETURNING id", "INSERT INTO tallies DEFAULT VALUES RETURNING id"]
              .map { |sql| adapter.decode(:int32, connection.execute(sql).dig(0, 0)) }

        assert_equal [1, 1], ids
      end
    end

    describe "on PostgreSQL" do
      let(:adapter) { postgres }
      let(:connection) { TestDatabase.empty("postgresql").connect }

      # Every statement in one transaction, as `skyward migrate` runs it.
      def migrate(sql)
        connection.execute("BEGIN")
        connection.execute_batch(sql)
        connection.execute("COMMIT")
      end

      class_exec(&running)

      it "fills a uuid primary key from its default" do
        migrate(section([create(fixtures::Visit)], :up))
        id = connection.execute("INSERT INTO visits DEFAULT VALUES RETURNING id").dig(0, 0)

        assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, id)
      end
    end

    describe "on SQLite" do
      let(:adapter) { sqlite }
      let(:connection) { sqlite.connect(":memory:") }

      # As `skyward migrate` runs a migration on SQLite: with foreign keys off,
      # since SQLite can't turn them off inside a transaction, and checked before
      # it commits.
      def migrate(sql)
        connection.execute("PRAGMA foreign_keys = OFF")
        connection.transaction do
          connection.execute_batch(sql)
          problems = connection.execute("PRAGMA foreign_key_check")
          raise SQLite3::ConstraintException, "foreign_key_check: #{problems.inspect}" unless problems.empty?
        end
      ensure
        connection.execute("PRAGMA foreign_keys = ON")
      end

      class_exec(&running)

      it "keeps the rows that reference a table it rebuilds, whatever they do ON DELETE" do
        items
        changes = diff([changed::CheckedOwner, changed::Item])
        migrate(section(changes, :up))
        kept = rows
        migrate(section(changes, :down))

        assert_equal [[[1, "Milk", "milk"]], [[1, "Milk", "milk"]]], [kept, rows]
      end

      it "keeps what the class can't declare when it rebuilds, recreating each index and copying each constraint" do
        created = section(diff([changed::Owner, changed::Item]), :up).sub(/(CREATE TABLE items \(.*?)\n\);/m) do
          "#{Regexp.last_match(1)},\n  CONSTRAINT items_pair_check CHECK (rank < length(title)),\n  CHECK (1 = 1)\n);"
        end
        migrate(<<~SQL)
          #{created}
          CREATE INDEX items_lower_title_index ON items (lower(title));
          CREATE INDEX items_noted_index ON items (id) WHERE note IS NOT NULL;
        SQL
        had = schema
        changes = diff([changed::Owner, changed::Unchecked])
        migrate(section(changes, :up))
        kept = schema.find { |table| table.name == :items }
        matched = diff([changed::Owner, changed::Unchecked])
        migrate(section(changes, :down))

        assert_equal(
          [["CHECK (1 = 1)", "CHECK (rank < length(title))"], %w[items_lower_title_index items_noted_index], [], had],
          [
            kept&.constraints.to_a.map(&:definition).grep(/rank|1 = 1/).sort,
            kept&.indexes.to_a.map(&:name).grep(/lower|noted/),
            matched,
            schema
          ]
        )
      end

      it "alters in place what SQLite's ALTER TABLE can, without rebuilding" do
        items
        sql = write(diff([changed::Owner, changed::Renamed]) + diff([changed::Owner, changed::Reindexed]))

        assert_equal <<~SQL, sql
          ALTER TABLE items RENAME COLUMN note TO remark;

          DROP INDEX items_owner_id_index;
          CREATE INDEX items_owner_id_status_index ON items (owner_id, status);

          -- down
          DROP INDEX items_owner_id_status_index;
          CREATE INDEX items_owner_id_index ON items (owner_id);
          ALTER TABLE items RENAME COLUMN remark TO note;
        SQL
      end

      it "rebuilds a table to change a column, and rebuilds it as it was to undo it" do
        items
        sql = write(diff([changed::Owner, changed::Required]))

        assert_equal <<~SQL, sql
          -- TODO: backfill the NULLs in items.note before it becomes NOT NULL
          CREATE TABLE items_new (
            id        INTEGER CONSTRAINT items_pkey PRIMARY KEY,
            owner_id  INTEGER NOT NULL CONSTRAINT items_owner_id_fkey REFERENCES owners ON DELETE CASCADE,
            title     TEXT    NOT NULL CONSTRAINT items_title_check CHECK (length(title) BETWEEN 1 AND 100),
            code      TEXT    NOT NULL CONSTRAINT items_code_key UNIQUE,
            status    TEXT    NOT NULL DEFAULT 'open' CONSTRAINT items_status_check CHECK (status IN ('open', 'closed')),
            note      TEXT    NOT NULL,
            rank      INTEGER
          );
          INSERT INTO items_new (id, owner_id, title, code, status, note, rank) SELECT id, owner_id, title, code, status, note, rank FROM items;
          DROP TABLE items;
          ALTER TABLE items_new RENAME TO items;
          CREATE INDEX items_owner_id_index ON items (owner_id);

          -- down
          CREATE TABLE items_new (
            id        INTEGER NOT NULL,
            owner_id  INTEGER NOT NULL,
            title     TEXT    NOT NULL,
            code      TEXT    NOT NULL,
            status    TEXT    NOT NULL DEFAULT 'open',
            note      TEXT,
            rank      INTEGER,
            CONSTRAINT items_pkey PRIMARY KEY (id),
            CONSTRAINT items_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES owners ON DELETE CASCADE,
            CONSTRAINT items_title_check CHECK (length(title) BETWEEN 1 AND 100),
            CONSTRAINT items_code_key UNIQUE (code),
            CONSTRAINT items_status_check CHECK (status IN ('open', 'closed'))
          );
          INSERT INTO items_new (id, owner_id, title, code, status, note, rank) SELECT id, owner_id, title, code, status, note, rank FROM items;
          DROP TABLE items;
          ALTER TABLE items_new RENAME TO items;
          CREATE INDEX items_owner_id_index ON items (owner_id);
        SQL
      end

      it "rebuilds to add a unique column, or one whose default is an expression, which ALTER TABLE can't" do
        items
        rebuilt = [changed::Added, changed::Serialed, changed::Stamped].map do |variant|
          write(diff([changed::Owner, variant])).start_with?("CREATE TABLE items_new")
        end

        assert_equal [false, true, true], rebuilt
      end

      it "keeps the type an untyped column has when it rebuilds, and drops a column the class no longer has" do
        connection.execute("CREATE TABLE scraps (id INTEGER PRIMARY KEY, payload BLOB NOT NULL, old TEXT NOT NULL)")
        scraps = sqlite.tables(connection).fetch(0)
        scrap = fixtures::Scrap
        edits = [
          migrations::DropColumn.new(column: scraps.columns.fetch(2)),
          migrations::AddConstraint.new(
            constraint: catalog::Constraint.new(
              name: "scraps_pkey", kind: :primary_key, columns: [:id], references: nil, definition: "PRIMARY KEY (id)"
            )
          )
        ]
        sql = write([alter(scrap, edits, table: scraps)])

        assert_equal <<~SQL, sql
          CREATE TABLE scraps_new (
            id       INTEGER CONSTRAINT scraps_pkey PRIMARY KEY,
            payload  BLOB    NOT NULL
          );
          INSERT INTO scraps_new (id, payload) SELECT id, payload FROM scraps;
          DROP TABLE scraps;
          ALTER TABLE scraps_new RENAME TO scraps;

          -- down
          -- scraps.old comes back empty: dropping it lost its data
          -- TODO: scraps.old needs a DEFAULT for the rows scraps already has
          CREATE TABLE scraps_new (
            id       INTEGER NOT NULL,
            payload  BLOB    NOT NULL,
            old      TEXT    NOT NULL,
            PRIMARY KEY (id)
          );
          INSERT INTO scraps_new (id, payload) SELECT id, payload FROM scraps;
          DROP TABLE scraps;
          ALTER TABLE scraps_new RENAME TO scraps;
        SQL
      end
    end
  end
end
