# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require_relative "../../../fixtures/migrations/migrations_fixtures"
require_relative "../../../fixtures/changes/changes_fixtures"
require_relative "../../../fixtures/tables/tables_fixtures"

describe Skyward::ORM::Migrations::Diff do
  fixtures = MigrationsFixtures
  changed = ChangesFixtures
  migrations = Skyward::ORM::Migrations
  catalog = Skyward::ORM::Catalog
  readers = %w[migrations changes tables].to_h do |name|
    signatures = File.expand_path("../../../fixtures/#{name}/sig", __dir__)
    [name, Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))]
  end

  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("migrations")) }
  let(:changes_types) { Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("changes")) }
  let(:asked) { [] }
  let(:yes) { [] }

  # Keeps each question, and says yes to the renames in yes.
  def rename
    lambda do |table, from, to|
      asked.push([table, from, to])
      yes.include?([from, to])
    end
  end

  def changes(classes, tables = [], types: column_types)
    Skyward::ORM::Migrations::Diff.changes(classes, types, tables, Skyward::ORM::Adapters::SQLite, rename)
  end

  def table(name, columns)
    Skyward::ORM::Catalog::Table.new(
      name:,
      columns: columns.map do |column|
        Skyward::ORM::Catalog::Column.new(name: column, type: "TEXT", nullable: true, default: nil)
      end,
      indexes: [],
      constraints: []
    )
  end

  # The owners and items tables as a migration creates them for Item, read
  # back from SQLite, with the items table changed by the block.
  def items(&change)
    connection = Skyward::ORM::Adapters::SQLite.connect(":memory:")
    created = [ChangesFixtures::Owner, ChangesFixtures::Item].map do |klass|
      Skyward::ORM::Migrations::CreateTable.new(klass:, columns: changes_types.columns(klass))
    end
    sql = Skyward::ORM::Migrations::Script.write(created, Skyward::ORM::Adapters::SQLite)
    connection.execute_batch(sql.split("-- down\n").fetch(0))
    Skyward::ORM::Adapters::SQLite.tables(connection).map do |table|
      table.name == :items && change ? yield(table) : table
    end
  end

  def item_table = items.find { |table| table.name == :items }

  def edits(klass, tables = items)
    changes([ChangesFixtures::Owner, klass], tables, types: changes_types).flat_map(&:edits)
  end

  def column(klass, name) = changes_types.columns(klass).find { |column| column.name == name }

  def renamed_columns(table, renames)
    table.with(columns: table.columns.map { |column| column.with(name: renames.fetch(column.name, column.name)) })
  end

  describe ".changes" do
    it "checks each class's declarations name its columns" do
      broken = Class.new(Skyward::ORM::Record) do
        index :missing
        attr_reader :id
      end

      error = assert_raises(Skyward::Core::BootError) { changes([broken]) }

      assert_equal "#{broken} has no column missing, which its index names. " \
                   "Add `attr_reader :missing`, or fix the name.",
                   error.message
    end

    it "refuses classes that share a table" do
      error = assert_raises(Skyward::Core::BootError) { changes([fixtures::Todo, fixtures::List, fixtures::NotedTodo]) }

      assert_equal "MigrationsFixtures::NotedTodo and MigrationsFixtures::Todo each declare table :todos. " \
                   "Give each table one class.",
                   error.message
    end

    it "creates each table the database doesn't have, with its class's typed columns" do
      assert_equal [migrations::CreateTable.new(klass: fixtures::List, columns: column_types.columns(fixtures::List))],
                   changes([fixtures::List])
    end

    it "creates each new table after the new tables it references, except itself, and otherwise by name" do
      created = changes([fixtures::Attachment, fixtures::Todo, fixtures::Member, fixtures::List])

      assert_equal(%i[lists members todos attachments], created.map { |change| change.klass.table_name })
    end

    it "goes on by name when new tables reference each other" do
      second = Class.new(Skyward::ORM::Record) { table :cycle_b }
      first = Class.new(Skyward::ORM::Record) { table :cycle_a }
      first.references :b_id, second
      second.references :a_id, first
      first.attr_reader :id, :b_id
      second.attr_reader :id, :a_id

      assert_equal(%i[cycle_a cycle_b], changes([second, first]).map { |change| change.klass.table_name })
    end

    it "alters each table that differs from its class after every new table, with its columns and the table it has" do
      todos = table(:todos, %i[id list_id title priority due_on done created_at])
      created, altered = changes([fixtures::NotedTodo, fixtures::Attachment], [todos])

      assert_equal [migrations::CreateTable, :attachments, :todos, column_types.columns(fixtures::NotedTodo), todos],
                   [created.class, created.klass.table_name, altered.klass.table_name, altered.columns, altered.table]
    end

    it "has nothing for a table that matches its class" do
      assert_empty changes([changed::Owner, changed::Item], items, types: changes_types)
    end

    it "leaves alone a table with no class, which may only not be loaded" do
      assert_empty changes([changed::Item], items, types: changes_types)
    end

    it "adds a column the table doesn't have" do
      assert_equal [migrations::AddColumn.new(column: column(changed::Added, :pinned))], edits(changed::Added)
    end

    it "writes a new column's own constraints with it, rather than adding them" do
      assert_equal [migrations::AddColumn.new(column: column(changed::Serialed, :serial))], edits(changed::Serialed)
    end

    it "drops a column its class doesn't have" do
      note = item_table.columns.find { |had| had.name == :note }

      assert_equal [migrations::DropColumn.new(column: note)], edits(changed::Dropped)
    end

    it "asks whether a column that went was renamed to a new one of a compatible type, and renames it on yes" do
      yes.push(%i[note remark])
      found = edits(changed::Renamed)

      assert_equal [[%i[items note remark]], [migrations::RenameColumn.new(from: :note, to: :remark)]], [asked, found]
    end

    it "drops one column and adds the other when it wasn't renamed" do
      note = item_table.columns.find { |had| had.name == :note }
      remark = column(changed::Renamed, :remark)

      assert_equal [migrations::DropColumn.new(column: note), migrations::AddColumn.new(column: remark)],
                   edits(changed::Renamed)
    end

    it "doesn't ask about a new column whose type isn't compatible" do
      tables = items do |had|
        had.with(
          columns: had.columns.map do |column|
            column.name == :rank ? column.with(name: :score, type: "TEXT") : column
          end
        )
      end
      found = edits(changed::Item, tables)

      assert_equal [[], [migrations::DropColumn, migrations::AddColumn]], [asked, found.map(&:class)]
    end

    it "asks about the next new column after a no, but not about one it's renamed to" do
      tables = items { |had| renamed_columns(had, { note: :old_note, title: :old_title }) }
      yes.push(%i[old_title note])
      edits(changed::Item, tables)

      assert_equal [%i[items old_title title], %i[items old_title note]], asked.first(2)
    end

    it "renames a renamed column's constraints, and keeps an index on it" do
      tables = items do |had|
        renamed = renamed_columns(had, { owner_id: :owner })
        renamed.with(
          constraints: had.constraints.map do |constraint|
            next constraint unless constraint.name == "items_owner_id_fkey"

            constraint.with(name: "items_owner_fkey", columns: [:owner])
          end,
          indexes: had.indexes.map { |index| index.with(columns: [:owner]) }
        )
      end
      yes.push(%i[owner owner_id])
      found = edits(changed::Item, tables)

      assert_equal(
        [
          [migrations::DropConstraint, "items_owner_fkey"],
          [migrations::RenameColumn, :owner],
          [migrations::AddConstraint, "items_owner_id_fkey"]
        ],
        found.map do |edit|
          [edit.class, edit.is_a?(migrations::RenameColumn) ? edit.from : edit.constraint.name]
        end
      )
    end

    it "changes the type of a column whose type isn't compatible, but not one whose type is" do
      tables = items do |had|
        had.with(columns: had.columns.map { |column| column.name == :owner_id ? column.with(type: "bigint") : column })
      end

      assert_equal [migrations::ChangeType.new(column: :rank, from: "INTEGER", to: "TEXT")],
                   edits(changed::Retyped, tables)
    end

    it "leaves a bool, Date or Time column declared BOOLEAN, DATE or DATETIME as it is" do
      connection = Skyward::ORM::Adapters::SQLite.connect(":memory:")
      created = [fixtures::List, fixtures::Todo].map do |klass|
        migrations::CreateTable.new(klass:, columns: column_types.columns(klass))
      end
      sql = migrations::Script.write(created, Skyward::ORM::Adapters::SQLite)
      connection.execute_batch(sql.split("-- down\n").fetch(0))
      declared = { done: "BOOLEAN", due_on: "DATE", created_at: "DATETIME(6)" }
      tables = Skyward::ORM::Adapters::SQLite.tables(connection).map do |table|
        next table unless table.name == :todos

        table.with(columns: table.columns.map { |column| column.with(type: declared.fetch(column.name, column.type)) })
      end

      assert_empty changes([fixtures::List, fixtures::Todo], tables)
    end

    it "makes a column required, or nullable, as its class says" do
      tables = items do |had|
        had.with(columns: had.columns.map { |column| column.name == :title ? column.with(nullable: true) : column })
      end

      assert_equal [
        migrations::ChangeNullable.new(column: :title, nullable: false),
        migrations::ChangeNullable.new(column: :note, nullable: false)
      ],
                   edits(changed::Required, tables)
    end

    it "has no type or nullability to compare for an untyped column" do
      untyped = Class.new(Skyward::ORM::Record) do
        table :items
        attr_reader :id, :title
      end
      key = catalog::Constraint.new(
        name: "items_pkey",
        kind: :primary_key,
        columns: [:id],
        references: nil,
        definition: "PRIMARY KEY (id)"
      )
      had = table(:items, %i[id title])
      tables = [had.with(columns: had.columns.map { |column| column.with(type: "BLOB") }, constraints: [key])]

      assert_empty changes([untyped], tables)
    end

    it "changes a default that differs from the one its class declares, or that it no longer has" do
      tables = items do |had|
        had.with(columns: had.columns.map { |column| column.name == :rank ? column.with(default: "0") : column })
      end

      assert_equal [
        migrations::ChangeDefault.new(column: :status, from: "'open'", to: "'closed'"),
        migrations::ChangeDefault.new(column: :rank, from: "0", to: nil)
      ],
                   edits(changed::Redefaulted, tables)
    end

    it "takes a DEFAULT NULL as no default, since PostgreSQL keeps none for it" do
      nulled = changed.item do
        default note: nil
        attr_reader(*changed::COLUMNS)
      end

      assert_empty edits(nulled).grep(migrations::ChangeDefault)
    end

    it "drops a constraint its class doesn't declare, and adds one it does" do
      title_check = item_table.constraints.find { |had| had.name == "items_title_check" }
      note_check = catalog::Constraint.new(
        name: "items_note_check",
        kind: :check,
        columns: [:note],
        references: nil,
        definition: "CHECK (length(note) <= 500)"
      )

      dropped = migrations::DropConstraint.new(constraint: title_check)
      added = migrations::AddConstraint.new(constraint: note_check)

      assert_equal [[dropped], [added]], [edits(changed::Unchecked), edits(changed::Checked)]
    end

    it "replaces a unique on other columns, and a reference that does something else ON DELETE" do
      found = [edits(changed::Paired), edits(changed::Restricted)].map do |list|
        list.map { |edit| [edit.class, edit.constraint.definition] }
      end

      assert_equal [
        [[migrations::DropConstraint, "UNIQUE (code)"], [migrations::AddConstraint, "UNIQUE (owner_id, code)"]],
        [
          [migrations::DropConstraint, "FOREIGN KEY (owner_id) REFERENCES owners ON DELETE CASCADE"],
          [migrations::AddConstraint, "FOREIGN KEY (owner_id) REFERENCES owners ON DELETE RESTRICT"]
        ]
      ],
                   found
    end

    it "matches a check by its name alone, whatever its expression and columns" do
      tables = items do |had|
        had.with(
          constraints: had.constraints.map do |constraint|
            if constraint.name == "items_title_check"
              constraint.with(columns: %i[title code], definition: "CHECK (x)")
            else
              constraint
            end
          end
        )
      end

      assert_empty edits(changed::Item, tables)
    end

    it "matches a constraint with no name, as SQLite can have, by its kind and columns" do
      tables = items { |had| had.with(constraints: had.constraints.map { |constraint| constraint.with(name: nil) }) }

      assert_empty edits(changed::Item, tables)
    end

    it "keeps an index on the same columns under another name, and replaces one on other columns" do
      tables = items { |had| had.with(indexes: had.indexes.map { |index| index.with(name: "items_by_owner") }) }
      reindexed = edits(changed::Reindexed).map { |edit| [edit.class, edit.index.name] }
      replaced = [
        [migrations::DropIndex, "items_owner_id_index"],
        [migrations::AddIndex, "items_owner_id_status_index"]
      ]

      assert_equal [[], replaced], [edits(changed::Item, tables), reindexed]
    end

    it "drops a unique index, which a class can't declare" do
      tables = items { |had| had.with(indexes: had.indexes.map { |index| index.with(unique: true) }) }

      assert_equal [migrations::DropIndex, migrations::AddIndex], edits(changed::Item, tables).map(&:class)
    end

    it "drops what a column has before the column, and adds what a column needs after it" do
      extra = catalog::Constraint.new(
        name: nil,
        kind: :check,
        columns: [:code],
        references: nil,
        definition: "CHECK (code <> '')"
      )
      gone = catalog::Column.new(name: :gone, type: "TEXT", nullable: true, default: nil)
      changed_columns = { title: { nullable: true }, rank: { default: "0" } }
      tables = items do |had|
        had.with(
          columns: [*had.columns.map { |column| column.with(**changed_columns.fetch(column.name, {})) }, gone],
          constraints: [*had.constraints.reject { |constraint| constraint.name == "items_title_check" }, extra],
          indexes: had.indexes.map { |index| index.with(columns: [:code]) }
        )
      end
      yes.push(%i[note remark])

      assert_equal [
        migrations::DropIndex, migrations::DropConstraint, migrations::DropColumn, migrations::RenameColumn,
        migrations::ChangeNullable, migrations::ChangeDefault, migrations::AddConstraint, migrations::AddIndex
      ],
                   edits(changed::Renamed, tables).map(&:class)
    end

    it "finds nothing to change once PostgreSQL has run the README's create_todos, and add_notes_to_todos undone" do
      readme = File.read(File.expand_path("../../../../README.md", __dir__))
      create_todos, add_notes = %w[create_todos add_notes_to_todos].map do |name|
        readme[%r{^-- db/migrate/\d+_#{name}\.sql\n(.*?)^```}m, 1].to_s.split("-- down\n")
      end
      types = Skyward::ORM::Tables::ColumnTypes.new(readers.fetch("tables"))
      postgresql = Skyward::ORM::Adapters::PostgreSQL
      connection = TestDatabase.empty("postgresql").connect
      matches = lambda do
        Skyward::ORM::Migrations::Diff.changes(
          [TablesFixtures::Todo], types, postgresql.tables(connection), postgresql, ->(*) { true }
        )
      end
      connection.execute("CREATE TABLE lists (id bigint PRIMARY KEY)")
      connection.execute_batch(create_todos.fetch(0))
      created = matches.call
      connection.execute_batch(add_notes.fetch(0))
      notes = postgresql.tables(connection).find { |table| table.name == :todos }&.columns&.last
      connection.execute_batch(add_notes.fetch(1))

      assert_equal [[], catalog::Column.new(name: :notes, type: "text", nullable: true, default: nil), []],
                   [created, notes, matches.call]
    end
  end
end
