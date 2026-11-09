# frozen_string_literal: true

require "test_helper"
require "sqlite3"
require "tmpdir"

describe Skyward::ORM::Migrations::Runner do
  runner = Skyward::ORM::Migrations::Runner
  sqlite = Skyward::ORM::Adapters::SQLite

  create_a = runner.parse("20261001000000_create_a.sql", "CREATE TABLE a (id INTEGER);\n\n-- down\nDROP TABLE a;\n")
  create_b = runner.parse(
    "20261002000000_create_b.sql",
    "CREATE TABLE b (id INTEGER);\nINSERT INTO b VALUES (1);\nINSERT INTO b VALUES (2);\n"
  )
  create_c = runner.parse("20261003000000_create_c.sql", "CREATE TABLE c (id INTEGER);\n")

  describe ".read" do
    it "reads each .sql file in the directory, in filename order" do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "20261002000000_create_b.sql"), "CREATE TABLE b (id INTEGER);\n")
        File.write(File.join(directory, "20261001000000_create_a.sql"), "CREATE TABLE a (id INTEGER);\n")
        File.write(File.join(directory, "README.md"), "Not a migration.\n")

        assert_equal [
          runner.parse("20261001000000_create_a.sql", "CREATE TABLE a (id INTEGER);\n"),
          runner.parse("20261002000000_create_b.sql", "CREATE TABLE b (id INTEGER);\n")
        ],
                     runner.read(directory)
      end
    end
  end

  describe ".parse" do
    it "takes the version from the file's name" do
      assert_equal "20261001000000", create_a.version
    end

    it "keeps the file's name" do
      assert_equal "20261001000000_create_a.sql", create_a.file
    end

    it "keeps only the part before the -- down line" do
      assert_equal "CREATE TABLE a (id INTEGER);\n\n", create_a.up
    end

    it "finds the -- down line with whitespace around it" do
      assert_equal "CREATE TABLE a (id INTEGER);\n",
                   runner.parse("1_a.sql", "CREATE TABLE a (id INTEGER);\n  -- down \t\nDROP TABLE a;\n").up
    end

    it "keeps the whole file when it has no -- down line, nor any line that only starts like one" do
      source = "CREATE TABLE a (id INTEGER);\n-- downgrade later\n"

      assert_equal source, runner.parse("1_a.sql", source).up
    end

    it "sums the up section with SHA-256" do
      assert_equal Digest::SHA256.hexdigest("CREATE TABLE a (id INTEGER);\n\n"), create_a.checksum
    end

    it "sums the same up section the same whatever the line endings, and whatever the down section" do
      edited = "CREATE TABLE a (id INTEGER);\r\n\r\n-- down\r\nDROP TABLE IF EXISTS a;\r\n"

      assert_equal create_a.checksum, runner.parse(create_a.file, edited).checksum
    end
  end

  describe ".run" do
    let(:connection) { sqlite.connect(":memory:") }

    def migrate(*migrations, adapter: Skyward::ORM::Adapters::SQLite)
      Skyward::ORM::Migrations::Runner.run(adapter, connection, migrations)
    end

    def tables = connection.execute("SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name").flatten

    it "records each version with its checksum and when it ran" do
      migrate(create_a)
      rows = connection.execute("SELECT version, checksum, ran_at FROM schema_migrations")
      ran = rows.map { |version, checksum, ran_at| [version, checksum, sqlite.decode(:time, ran_at).class] }

      assert_equal [["20261001000000", create_a.checksum, Time]], ran
    end

    it "refuses to run anything when migrations changed after they ran, naming each" do
      migrate(create_a, create_b)
      edited = [create_a, create_b].map { |migration| runner.parse(migration.file, "SELECT 1;\n") }

      assert_equal [runner::Edited.new(files: [create_a.file, create_b.file]), %w[a b schema_migrations]],
                   [migrate(*edited, create_c), tables]
    end

    it "skips a migration that has run" do
      migrate(create_a)

      assert_equal ["20261002000000"], migrate(create_a, create_b)
    end

    it "runs the rest when a migration that ran has no file anymore" do
      migrate(create_a, create_b)

      assert_equal ["20261003000000"], migrate(create_b, create_c)
    end

    it "runs each migration in order and returns their versions" do
      assert_equal %w[20261001000000 20261002000000], migrate(create_a, create_b)
    end

    it "runs nothing when it can't take the migration lock, naming the file and the database's message" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "todos.db")
        holder = sqlite.connect(path)
        waiter = sqlite.connect(path)
        runner.run(sqlite, waiter, [])
        holder.execute("BEGIN IMMEDIATE")
        waiter.busy_handler_timeout = 10
        locked = runner.run(sqlite, waiter, [create_a, create_b])

        assert_equal [runner::Locked.new(file: create_a.file, message: "database is locked"), false, [[1]]],
                     [locked, waiter.transaction_active?, waiter.execute("PRAGMA foreign_keys")]
      end
    end

    it "turns foreign keys back on after a migration, and after one that fails" do
      broken = runner.parse("20261002000000_broken.sql", "INSERT INTO nowhere VALUES (1);\n")
      after = [create_a, broken].map do |migration|
        migrate(migration)
        connection.execute("PRAGMA foreign_keys")
      end

      assert_equal [[[1]], [[1]]], after
    end

    it "skips a migration another migrator ran after this one read what had run" do
      # Runs create_a for the other migrator, after this one has read schema_migrations.
      racing = Module.new do
        extend Skyward::ORM::Adapters::SQLite

        def self.begin_migration
          "INSERT OR IGNORE INTO schema_migrations (version, checksum) VALUES ('20261001000000', 'theirs'); " \
            "BEGIN IMMEDIATE"
        end
      end

      assert_equal [["20261002000000"], %w[b schema_migrations]], [migrate(create_a, create_b, adapter: racing), tables]
    end

    it "runs every statement in a migration" do
      migrate(create_b)

      assert_equal [[1], [2]], connection.execute("SELECT id FROM b ORDER BY id")
    end

    it "rolls back a migration that fails, runs nothing after it, and returns the file and the database's message" do
      broken = runner.parse(
        "20261002000000_broken.sql",
        "CREATE TABLE d (id INTEGER);\nINSERT INTO nowhere VALUES (1);\n"
      )
      failed = runner::Failed.new(
        file: broken.file,
        message: "no such table: nowhere:\nINSERT INTO nowhere VALUES (1);"
      )

      assert_equal [failed, %w[a schema_migrations], [["20261001000000"]]],
                   [
                     migrate(create_a, broken, create_c),
                     tables,
                     connection.execute("SELECT version FROM schema_migrations")
                   ]
    end

    it "rolls back a migration that leaves a row referring to a missing one, naming each such row" do
      connection.execute_batch(<<~SQL)
        CREATE TABLE lists (id INTEGER PRIMARY KEY);
        CREATE TABLE todos (id INTEGER PRIMARY KEY, list_id INTEGER NOT NULL REFERENCES lists);
      SQL
      dangling = runner.parse("20261001000000_add_todo.sql", "INSERT INTO todos (list_id) VALUES (9);\n")
      failed = runner::Failed.new(
        file: dangling.file,
        message: "foreign key check failed: todos row 1 refers to a missing lists row (foreign key 0)"
      )

      assert_equal [failed, [], []],
                   [
                     migrate(dangling),
                     connection.execute("SELECT id FROM todos"),
                     connection.execute("SELECT version FROM schema_migrations")
                   ]
    end

    it "rolls back a migration whose version can't be recorded, as when it drops schema_migrations" do
      dropping = runner.parse(
        "20261002000000_drop.sql",
        "CREATE TABLE d (id INTEGER);\nDROP TABLE schema_migrations;\n"
      )
      migrate(create_a)
      failed = runner::Failed.new(
        file: dropping.file,
        message: "no such table: schema_migrations:\nINSERT INTO schema_migrations (version, checksum) VALUES (?, ?)"
      )

      assert_equal [failed, %w[a schema_migrations], false], [migrate(dropping), tables, connection.transaction_active?]
    end

    it "rolls back a migration that can't commit, as when another connection is reading" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "todos.db")
        waiter = sqlite.connect(path)
        runner.run(sqlite, waiter, [])
        reader = sqlite.connect(path)
        reader.execute("BEGIN")
        reader.execute("SELECT version FROM schema_migrations")
        waiter.busy_handler_timeout = 10
        failed = runner::Failed.new(file: create_a.file, message: "database is locked")

        assert_equal [failed, false, [["schema_migrations"]]],
                     [
                       runner.run(sqlite, waiter, [create_a]),
                       waiter.transaction_active?,
                       waiter.execute("SELECT name FROM sqlite_schema WHERE type = 'table'")
                     ]
      end
    end

    it "rolls back, then turns foreign keys back on, when a migration is left by throw or a killed thread" do
      leaving = Module.new do
        extend Skyward::ORM::Adapters::SQLite

        define_singleton_method(:foreign_key_violations) { |_connection| throw :left }
      end
      catch(:left) { migrate(create_a, adapter: leaving) }

      assert_equal [false, [[1]], %w[schema_migrations]],
                   [connection.transaction_active?, connection.execute("PRAGMA foreign_keys"), tables]
    end

    it "returns the failure of a migration SQLite rolled back itself, as ON CONFLICT ROLLBACK does" do
      connection.execute("CREATE TABLE d (id INTEGER PRIMARY KEY ON CONFLICT ROLLBACK)")
      conflicting = runner.parse("20261001000000_conflict.sql", "INSERT INTO d VALUES (1);\n" * 2)
      failed = runner::Failed.new(file: conflicting.file, message: "UNIQUE constraint failed: d.id")

      assert_equal [failed, false, []],
                   [migrate(conflicting), connection.transaction_active?, connection.execute("SELECT id FROM d")]
    end

    it "runs each migration once when two migrators start together on one database" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "todos.db")
        sqlite.connect(path).execute("CREATE TABLE runs (version TEXT NOT NULL)")
        counted = (10..19).map do |number|
          runner.parse("#{number}_count.sql", "INSERT INTO runs (version) VALUES ('#{number}');\n")
        end
        # Neither takes the lock until both have read that nothing has run, so
        # both try every migration. The driver holds Ruby's lock while SQLite
        # works, so the one migrating sleeps where it asks for a placeholder,
        # inside its transaction, for the other to try to take the lock then.
        arrived = Queue.new
        together = Thread.new { 2.times { arrived.pop } }
        adapter = Module.new do
          extend Skyward::ORM::Adapters::SQLite

          define_singleton_method(:begin_migration) do
            arrived << true
            together.join
            super()
          end

          define_singleton_method(:placeholder) do |position|
            sleep 0.002
            super(position)
          end
        end
        migrators = Array.new(2) do
          connection = sqlite.connect(path)
          Thread.new { runner.run(adapter, connection, counted) }
        end
        ran = migrators.flat_map(&:value).sort
        runs = sqlite.connect(path).execute("SELECT version FROM runs ORDER BY version").flatten

        assert_equal [counted.map(&:version), counted.map(&:version)], [ran, runs]
      end
    end
  end

  describe ".message" do
    it "names each migration that changed after it ran" do
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
                   "so neither it nor any later migration ran: database is locked",
                   runner.message(runner::Locked.new(file: create_a.file, message: "database is locked"))
    end

    it "names the migration that failed, with the database's message" do
      assert_equal "20261001000000_create_a.sql failed, so it was rolled back and no later migration ran: " \
                   "no such table: nowhere",
                   runner.message(runner::Failed.new(file: create_a.file, message: "no such table: nowhere"))
    end
  end
end
