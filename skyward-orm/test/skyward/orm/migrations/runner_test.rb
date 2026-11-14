# frozen_string_literal: true

require 'delegate'
require 'test_helper'
require 'sqlite3'
require 'tmpdir'

describe Skyward::ORM::Migrations::Runner do
  runner = Skyward::ORM::Migrations::Runner
  sqlite = Skyward::ORM::Adapters::SQLite

  create_a = runner.parse('20261001000000_create_a.sql', "CREATE TABLE a (id INTEGER);\n\n-- down\nDROP TABLE a;\n")
  create_b = runner.parse(
    '20261002000000_create_b.sql',
    "CREATE TABLE b (id INTEGER);\nINSERT INTO b VALUES (1);\nINSERT INTO b VALUES (2);\n"
  )
  create_c = runner.parse('20261003000000_create_c.sql', "CREATE TABLE c (id INTEGER);\n")

  on_sqlite = proc do
    let(:empty) { TestDatabase.empty('sqlite') }
    let(:adapter) { Skyward::ORM::Adapters::SQLite }

    def idle? = !connection.transaction_active?
  end

  on_postgresql = proc do
    let(:empty) { TestDatabase.empty('postgresql') }
    let(:adapter) { Skyward::ORM::Adapters::PostgreSQL }

    # As another session sees it, which tells an open transaction from none.
    def idle?
      pid = connection.execute('SELECT pg_backend_pid()').dig(0, 0)
      empty.connect.execute('SELECT state FROM pg_stat_activity WHERE pid = $1', [pid]) == [['idle']]
    end
  end

  let(:connection) { empty.connect }

  def migrate(*migrations, adapter: self.adapter)
    Skyward::ORM::Migrations::Runner.run(adapter, connection, migrations)
  end

  def tables = adapter.tables(connection).map { |table| table.name.name }.sort

  describe '.read' do
    it 'reads each .sql file in the directory, in filename order' do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, '20261002000000_create_b.sql'), "CREATE TABLE b (id INTEGER);\n")
        File.write(File.join(directory, '20261001000000_create_a.sql'), "CREATE TABLE a (id INTEGER);\n")
        File.write(File.join(directory, 'README.md'), "Not a migration.\n")

        assert_equal [
          runner.parse('20261001000000_create_a.sql', "CREATE TABLE a (id INTEGER);\n"),
          runner.parse('20261002000000_create_b.sql', "CREATE TABLE b (id INTEGER);\n")
        ],
                     runner.read(directory)
      end
    end
  end

  describe '.parse' do
    it "takes the version from the file's name" do
      assert_equal '20261001000000', create_a.version
    end

    it "keeps the file's name" do
      assert_equal '20261001000000_create_a.sql', create_a.file
    end

    it 'keeps only the part before the -- down line' do
      assert_equal "CREATE TABLE a (id INTEGER);\n\n", create_a.up
    end

    it 'keeps the part after the -- down line as the down section' do
      assert_equal "\nDROP TABLE a;\n", create_a.down
    end

    it 'has an empty down section when it has no -- down line' do
      assert_equal '', create_b.down
    end

    it 'finds the -- down line with whitespace around it' do
      assert_equal "CREATE TABLE a (id INTEGER);\n",
                   runner.parse('1_a.sql', "CREATE TABLE a (id INTEGER);\n  -- down \t\nDROP TABLE a;\n").up
    end

    it 'keeps the whole file when it has no -- down line, nor any line that only starts like one' do
      source = "CREATE TABLE a (id INTEGER);\n-- downgrade later\n"

      assert_equal source, runner.parse('1_a.sql', source).up
    end

    it 'sums the up section with SHA-256' do
      assert_equal Digest::SHA256.hexdigest("CREATE TABLE a (id INTEGER);\n\n"), create_a.checksum
    end

    it 'sums the same up section the same whatever the line endings, and whatever the down section' do
      edited = "CREATE TABLE a (id INTEGER);\r\n\r\n-- down\r\nDROP TABLE IF EXISTS a;\r\n"

      assert_equal create_a.checksum, runner.parse(create_a.file, edited).checksum
    end
  end

  describe '.run' do
    # What running migrations does on every database, so each runs these.
    running = proc do
      # Runs create_a for the other migrator, after this one has read
      # schema_migrations: the first lock it takes is for making that table.
      let(:racing) do
        racing_on = adapter
        locks = 0
        Module.new do
          extend racing_on

          define_singleton_method(:begin_migration) do
            locks += 1
            next super() if locks == 1

            "INSERT INTO schema_migrations (version, checksum) VALUES ('20261001000000', 'theirs') " \
              "ON CONFLICT DO NOTHING; #{super()}"
          end
        end
      end

      it 'records each version with its checksum and when it ran' do
        migrate(create_a)
        rows = connection.execute('SELECT version, checksum, ran_at FROM schema_migrations')
        ran = rows.map do |version, checksum, ran_at|
          [version, checksum, adapter.decode(TestDatabase.column(:time), ran_at).class]
        end

        assert_equal [['20261001000000', create_a.checksum, Time]], ran
      end

      it 'refuses to run anything when migrations changed after they ran, naming each' do
        migrate(create_a, create_b)
        edited = [create_a, create_b].map { |migration| runner.parse(migration.file, "SELECT 1;\n") }

        assert_equal [runner::Edited.new(files: [create_a.file, create_b.file]), %w[a b schema_migrations]],
                     [migrate(*edited, create_c), tables]
      end

      it 'skips a migration that has run' do
        migrate(create_a)

        assert_equal ['20261002000000'], migrate(create_a, create_b)
      end

      it 'runs the rest when a migration that ran has no file anymore' do
        migrate(create_a, create_b)

        assert_equal ['20261003000000'], migrate(create_b, create_c)
      end

      it "raises when it can't make schema_migrations, and leaves no transaction open" do
        broken_on = adapter
        broken = Module.new do
          extend broken_on

          def self.sql_type(_column) = '('
        end

        assert_raises(StandardError) { runner.run(broken, connection, [create_a]) }
        assert_equal [true, []], [idle?, tables]
      end

      it 'runs each migration in order and returns their versions' do
        assert_equal %w[20261001000000 20261002000000], migrate(create_a, create_b)
      end

      it 'skips a migration another migrator ran after this one read what had run' do
        assert_equal [['20261002000000'], %w[b schema_migrations]],
                     [migrate(create_a, create_b, adapter: racing), tables]
      end

      it 'runs every statement in a migration' do
        migrate(create_b)

        assert_equal(
          [1, 2],
          connection.execute('SELECT id FROM b ORDER BY id').map do |(id)|
            adapter.decode(TestDatabase.column(:integer), id)
          end
        )
      end

      it "rolls back a migration that fails, runs nothing after it, and returns the file and the database's message" do
        broken = runner.parse(
          '20261002000000_broken.sql',
          "CREATE TABLE d (id INTEGER);\nINSERT INTO nowhere VALUES (1);\n"
        )
        failed = runner::Failed.new(file: broken.file, message: messages.fetch(:nowhere))

        assert_equal [failed, %w[a schema_migrations], [['20261001000000']]],
                     [
                       migrate(create_a, broken, create_c),
                       tables,
                       connection.execute('SELECT version FROM schema_migrations')
                     ]
      end

      it "rolls back a migration whose version can't be recorded, as when it drops schema_migrations" do
        dropping = runner.parse(
          '20261002000000_drop.sql',
          "CREATE TABLE d (id INTEGER);\nDROP TABLE schema_migrations;\n"
        )
        migrate(create_a)
        failed = runner::Failed.new(file: dropping.file, message: messages.fetch(:recording))

        assert_equal [failed, %w[a schema_migrations], true], [migrate(dropping), tables, idle?]
      end

      it 'runs each migration once when two migrators start together on one database' do
        empty.connect.execute('CREATE TABLE runs (version TEXT NOT NULL)')
        counted = (10..19).map do |number|
          runner.parse("#{number}_count.sql", "INSERT INTO runs (version) VALUES ('#{number}');\n")
        end
        # Both make schema_migrations at once, and neither takes the lock for a
        # migration until both have read that nothing has run, so both try every
        # migration. A round gives up waiting for a migrator that never comes, as
        # when it failed, so the test fails rather than hangs. The one migrating
        # sleeps where it asks for a placeholder, inside its transaction, for the
        # other to try to take the lock then: SQLite's driver holds Ruby's lock
        # while SQLite works.
        rounds = Array.new(2) do
          arrived = Queue.new
          [arrived, Thread.new { 2.times { arrived.pop(timeout: 5) } }]
        end
        migrating_on = adapter
        both = Module.new do
          extend migrating_on

          define_singleton_method(:begin_migration) do
            round = Thread.current[:migration_round] = Thread.current[:migration_round].to_i + 1
            arrived, together = rounds[round - 1]
            if together
              arrived << true
              together.join
            end
            super()
          end

          define_singleton_method(:placeholder) do |position|
            sleep 0.002
            super(position)
          end
        end
        migrators = Array.new(2) do
          migrating = empty.connect
          Thread.new { runner.run(both, migrating, counted) }
        end
        ran = migrators.flat_map(&:value).sort
        runs = empty.connect.execute('SELECT version FROM runs ORDER BY version').flatten

        assert_equal [counted.map(&:version), counted.map(&:version)], [ran, runs]
      end
    end

    describe 'on SQLite' do
      class_exec(&on_sqlite)

      let(:messages) do
        {
          nowhere: "no such table: nowhere:\nINSERT INTO nowhere VALUES (1);",
          recording: "no such table: schema_migrations:\n" \
                     'INSERT INTO schema_migrations (version, checksum) VALUES (?, ?)'
        }
      end

      class_exec(&running)

      it "runs nothing when it can't take the migration lock to make schema_migrations" do
        holder = empty.connect
        holder.execute('BEGIN IMMEDIATE')
        connection.busy_handler_timeout = 10
        locked = runner::Locked.new(file: create_a.file, message: 'database is locked')

        assert_equal [[], locked, true, []],
                     [runner.run(sqlite, connection, []), runner.run(sqlite, connection, [create_a]), idle?, tables]
      end

      it "runs nothing when it can't take the migration lock, naming the file and the database's message" do
        holder = empty.connect
        runner.run(sqlite, connection, [])
        holder.execute('BEGIN IMMEDIATE')
        connection.busy_handler_timeout = 10
        locked = runner.run(sqlite, connection, [create_a, create_b])

        assert_equal [runner::Locked.new(file: create_a.file, message: 'database is locked'), true, [[1]]],
                     [locked, idle?, connection.execute('PRAGMA foreign_keys')]
      end

      it 'turns foreign keys back on after a migration, and after one that fails' do
        broken = runner.parse('20261002000000_broken.sql', "INSERT INTO nowhere VALUES (1);\n")
        after = [create_a, broken].map do |migration|
          migrate(migration)
          connection.execute('PRAGMA foreign_keys')
        end

        assert_equal [[[1]], [[1]]], after
      end

      it 'rolls back a migration that leaves a row referring to a missing one, naming each such row' do
        connection.execute_batch(<<~SQL)
          CREATE TABLE lists (id INTEGER PRIMARY KEY);
          CREATE TABLE todos (id INTEGER PRIMARY KEY, list_id INTEGER NOT NULL REFERENCES lists);
        SQL
        dangling = runner.parse('20261001000000_add_todo.sql', "INSERT INTO todos (list_id) VALUES (9);\n")
        failed = runner::Failed.new(
          file: dangling.file,
          message: 'foreign key check failed: todos row 1 refers to a missing lists row (foreign key 0)'
        )

        assert_equal [failed, [], []],
                     [
                       migrate(dangling),
                       connection.execute('SELECT id FROM todos'),
                       connection.execute('SELECT version FROM schema_migrations')
                     ]
      end

      it "rolls back a migration that can't commit, as when another connection is reading" do
        runner.run(sqlite, connection, [])
        reader = empty.connect
        reader.execute('BEGIN')
        reader.execute('SELECT version FROM schema_migrations')
        connection.busy_handler_timeout = 10
        failed = runner::Failed.new(file: create_a.file, message: 'database is locked')

        assert_equal [failed, true, %w[schema_migrations]], [runner.run(sqlite, connection, [create_a]), idle?, tables]
      end

      it 'rolls back, then turns foreign keys back on, when a migration is left by throw or a killed thread' do
        leaving = Module.new do
          extend Skyward::ORM::Adapters::SQLite

          define_singleton_method(:foreign_key_violations) { |_connection| throw :left }
        end
        catch(:left) { migrate(create_a, adapter: leaving) }

        assert_equal [true, [[1]], %w[schema_migrations]], [idle?, connection.execute('PRAGMA foreign_keys'), tables]
      end

      it 'returns the failure of a migration SQLite rolled back itself, as ON CONFLICT ROLLBACK does' do
        connection.execute('CREATE TABLE d (id INTEGER PRIMARY KEY ON CONFLICT ROLLBACK)')
        conflicting = runner.parse('20261001000000_conflict.sql', "INSERT INTO d VALUES (1);\n" * 2)
        failed = runner::Failed.new(file: conflicting.file, message: 'UNIQUE constraint failed: d.id')

        assert_equal [failed, true, []], [migrate(conflicting), idle?, connection.execute('SELECT id FROM d')]
      end
    end

    describe 'on PostgreSQL' do
      class_exec(&on_postgresql)

      let(:messages) do
        {
          nowhere: "ERROR:  relation \"nowhere\" does not exist\nLINE 2: INSERT INTO nowhere VALUES (1);\n" \
                   "#{' ' * 20}^\n",
          recording: "ERROR:  relation \"schema_migrations\" does not exist\n" \
                     "LINE 1: INSERT INTO schema_migrations (version, checksum) VALUES ($1...\n#{' ' * 20}^\n"
        }
      end

      class_exec(&running)

      it "runs nothing when it can't take the migration lock to make schema_migrations" do
        holder = empty.connect
        holder.execute_batch(adapter.begin_migration)
        connection.execute("SET lock_timeout = '10ms'")
        locked = runner::Locked.new(file: create_a.file, message: "ERROR:  canceling statement due to lock timeout\n")

        assert_equal [[], locked, true, []],
                     [runner.run(adapter, connection, []), runner.run(adapter, connection, [create_a]), idle?, tables]
      end

      it "runs nothing when it can't take the migration lock, and leaves no transaction open" do
        holder = empty.connect
        runner.run(adapter, connection, [])
        holder.execute_batch(adapter.begin_migration)
        connection.execute("SET lock_timeout = '10ms'")
        locked = runner.run(adapter, connection, [create_a, create_b])
        timed_out = runner::Locked.new(
          file: create_a.file,
          message: "ERROR:  canceling statement due to lock timeout\n"
        )

        assert_equal [timed_out, true, %w[schema_migrations]], [locked, idle?, tables]
      end

      it 'sends nothing to end a migration, since its lock ends with its transaction' do
        batches = []
        recording = SimpleDelegator.new(connection)
        recording.define_singleton_method(:execute_batch) do |sql|
          batches << sql
          __getobj__.execute_batch(sql)
        end
        runner.run(adapter, recording, [create_a])

        assert_equal [adapter.begin_migration, adapter.begin_migration, create_a.up], batches
      end

      it 'fails a migration that leaves a row referring to a missing one, as PostgreSQL checks it as it writes' do
        connection.execute('CREATE TABLE lists (id bigint PRIMARY KEY)')
        connection.execute('CREATE TABLE todos (id bigint PRIMARY KEY, list_id bigint NOT NULL REFERENCES lists)')
        dangling = runner.parse('20261001000000_add_todo.sql', "INSERT INTO todos (id, list_id) VALUES (1, 9);\n")
        failed = migrate(dangling)

        assert_equal [runner::Failed, dangling.file, [], []],
                     [
                       failed.class,
                       failed.file,
                       connection.execute('SELECT id FROM todos'),
                       connection.execute('SELECT version FROM schema_migrations')
                     ]
      end
    end
  end

  describe '.rollback' do
    create_d = runner.parse('20261004000000_create_d.sql', "CREATE TABLE d (id INTEGER);\n\n-- down\nDROP TABLE d;\n")

    # What rolling back does on every database, so each runs these.
    rolling_back = proc do
      # Rolls create_d back for the other migrator, after this one has read the latest version.
      let(:racing) do
        racing_on = adapter
        Module.new do
          extend racing_on

          def self.begin_migration = "DELETE FROM schema_migrations WHERE version = '20261004000000'; #{super}"
        end
      end

      def roll_back(*migrations, adapter: self.adapter)
        Skyward::ORM::Migrations::Runner.rollback(adapter, connection, migrations)
      end

      def versions = connection.execute('SELECT version FROM schema_migrations ORDER BY version').flatten

      it "has nothing to roll back on a database that's never been migrated, and doesn't make schema_migrations" do
        assert_equal [:nothing, []], [roll_back(create_a), tables]
      end

      it 'has nothing to roll back when no migration has run' do
        migrate

        assert_equal :nothing, roll_back(create_a)
      end

      it "refuses when the latest migration's file is gone, naming its version" do
        migrate(create_a, create_d)

        assert_equal [runner::Missing.new(version: create_d.version), %w[a d schema_migrations]],
                     [roll_back(create_a), tables]
      end

      it 'refuses a migration whose down section is blank, naming the file' do
        blank = runner.parse('20261004000000_create_e.sql', "CREATE TABLE e (id INTEGER);\n-- down\n  \n\n")
        migrate(blank)

        assert_equal [runner::Irreversible.new(file: blank.file), [blank.version]], [roll_back(blank), versions]
      end

      it "runs the latest migration's down section, deletes its version, and returns it" do
        migrate(create_a, create_d)

        assert_equal [create_d.version, %w[a schema_migrations], [create_a.version]],
                     [roll_back(create_a, create_d), tables, versions]
      end

      it 'rolls back the greatest version, which sorts last, though another ran after it' do
        migrate(create_d)
        migrate(create_a, create_d)

        assert_equal [create_d.version, [create_a.version]], [roll_back(create_a, create_d), versions]
      end

      it 'rolls back nothing when another migrator rolled back the latest after this one read it' do
        migrate(create_a, create_d)

        assert_equal [runner::Raced.new(file: create_d.file), %w[a d schema_migrations]],
                     [roll_back(create_a, create_d, adapter: racing), tables]
      end

      it "undoes a down section that fails, keeping its version, and returns the file and the database's message" do
        failing = runner.parse(
          '20261004000000_create_e.sql',
          "CREATE TABLE e (id INTEGER);\n-- down\nDROP TABLE e;\nDROP TABLE nowhere;\n"
        )
        migrate(failing)
        failed = runner::Failed.new(file: failing.file, message: dropped_nowhere)

        assert_equal [failed, %w[e schema_migrations], [failing.version], true],
                     [roll_back(failing), tables, versions, idle?]
      end
    end

    describe 'on SQLite' do
      class_exec(&on_sqlite)

      let(:dropped_nowhere) { "no such table: nowhere:\nDROP TABLE nowhere;" }

      class_exec(&rolling_back)

      it "rolls back nothing when it can't take the migration lock, naming the file and the database's message" do
        migrate(create_d)
        holder = empty.connect
        holder.execute('BEGIN IMMEDIATE')
        connection.busy_handler_timeout = 10

        assert_equal [runner::Locked.new(file: create_d.file, message: 'database is locked'), true],
                     [roll_back(create_d), idle?]
      end

      it 'undoes a down section that leaves a row referring to a missing one, naming each such row' do
        parent = runner.parse(
          '20261004000000_create_lists.sql',
          "CREATE TABLE lists (id INTEGER PRIMARY KEY);\n" \
          "CREATE TABLE todos (id INTEGER PRIMARY KEY, list_id INTEGER NOT NULL REFERENCES lists);\n" \
          "INSERT INTO lists (id) VALUES (1);\nINSERT INTO todos (list_id) VALUES (1);\n" \
          "-- down\nDROP TABLE lists;\n"
        )
        migrate(parent)
        failed = runner::Failed.new(
          file: parent.file,
          message: 'foreign key check failed: todos row 1 refers to a missing lists row (foreign key 0)'
        )

        assert_equal [failed, %w[lists schema_migrations todos], [parent.version]],
                     [roll_back(parent), tables, versions]
      end
    end

    describe 'on PostgreSQL' do
      class_exec(&on_postgresql)

      let(:dropped_nowhere) { "ERROR:  table \"nowhere\" does not exist\n" }

      class_exec(&rolling_back)

      it "rolls back nothing when it can't take the migration lock, and leaves no transaction open" do
        migrate(create_d)
        holder = empty.connect
        holder.execute_batch(adapter.begin_migration)
        connection.execute("SET lock_timeout = '10ms'")
        timed_out = runner::Locked.new(
          file: create_d.file,
          message: "ERROR:  canceling statement due to lock timeout\n"
        )

        assert_equal [timed_out, true, [create_d.version]], [roll_back(create_d), idle?, versions]
      end
    end
  end

  describe '.message' do
    it 'names each migration that changed after it ran' do
      expected = <<~MESSAGE.chomp
        These migrations changed after they ran, so none ran:
          20261001000000_create_a.sql
          20261002000000_create_b.sql
        Put each back as it was, and make the change in a new migration. Only a -- down section can change.
      MESSAGE

      assert_equal expected, runner.message(runner::Edited.new(files: [create_a.file, create_b.file]))
    end

    it "names the migration that couldn't take the lock, with the database's message" do
      assert_equal "20261001000000_create_a.sql couldn't take the migration lock, which another migrator may hold, " \
                   'so neither it nor any later migration ran: database is locked',
                   runner.message(runner::Locked.new(file: create_a.file, message: 'database is locked'))
    end

    it "names the migration that failed, with the database's message" do
      assert_equal '20261001000000_create_a.sql failed, so it was rolled back and no later migration ran: ' \
                   'no such table: nowhere',
                   runner.message(runner::Failed.new(file: create_a.file, message: 'no such table: nowhere'))
    end
  end

  describe '.rollback_message' do
    it "says there's nothing to roll back" do
      assert_equal "No migration has run, so there's nothing to roll back.", runner.rollback_message(:nothing)
    end

    it 'names the latest version, whose file is gone' do
      assert_equal "20261001000000 is the latest migration to have run, but its file is gone, so it can't be rolled " \
                   'back. Put its file back to roll it back.',
                   runner.rollback_message(runner::Missing.new(version: '20261001000000'))
    end

    it 'names the migration with nothing in its down section' do
      assert_equal "20261001000000_create_a.sql has nothing in its -- down section, so it wasn't rolled back. " \
                   'Write the SQL that undoes it there.',
                   runner.rollback_message(runner::Irreversible.new(file: create_a.file))
    end

    it 'names the migration another migrator moved past' do
      assert_equal "20261001000000_create_a.sql isn't the latest migration anymore, since another migrator ran or " \
                   "rolled back one while this one waited for the lock, so it wasn't rolled back.",
                   runner.rollback_message(runner::Raced.new(file: create_a.file))
    end

    it "names the migration that couldn't take the lock, with the database's message" do
      assert_equal "20261001000000_create_a.sql couldn't take the migration lock, which another migrator may hold, " \
                   "so it wasn't rolled back: database is locked",
                   runner.rollback_message(runner::Locked.new(file: create_a.file, message: 'database is locked'))
    end

    it "names the migration whose down section failed, with the database's message" do
      assert_equal 'Rolling back 20261001000000_create_a.sql failed, so its -- down section was undone and it still ' \
                   'counts as run: no such table: nowhere',
                   runner.rollback_message(runner::Failed.new(file: create_a.file, message: 'no such table: nowhere'))
    end
  end
end
