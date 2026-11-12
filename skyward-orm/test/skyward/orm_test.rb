# frozen_string_literal: true

require "open3"
require "test_helper"
require_relative "../fixtures/tables/tables_fixtures"

describe Skyward::ORM do
  it "loads every file under its own part of the Skyward namespace" do
    # Eager loading raises if any file's name doesn't match its constant.
    Zeitwerk::Loader.eager_load_all

    assert_includes Zeitwerk::Loader.all_dirs, File.expand_path("../../lib/skyward", __dir__)
  end

  it "registers its signatures, which an app's table classes subclass" do
    builder = Skyward::Core::Signatures.load(File.expand_path("missing", __dir__))

    assert builder.env.class_decl?(RBS::TypeName.parse("::Skyward::ORM::Record"))
  end
end

describe Skyward do
  fixtures = File.expand_path("../fixtures/tables", __dir__)

  let(:empty) { TestDatabase.empty }

  describe ".connect" do
    todo = TablesFixtures::Todo
    priority = Class.new(Skyward::ORM::Record) { attr_reader :priority }

    it "keeps the database it connects to, for every query" do
      database = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)

      assert_same database, Skyward::ORM::Connection::SESSION.database
    end

    it "reads column types from the signatures given" do
      database = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)

      assert_equal :normal, database.decoder(todo, priority, []).call(["normal"]).priority
    end

    it "reads them from sig/ in the current directory by default" do
      database = Dir.chdir(fixtures) { Skyward.connect(empty.url, check: false) }

      assert_equal :normal, database.decoder(todo, priority, []).call(["normal"]).priority
    end

    it "reads Skyward ORM's aliases as the column types they name" do
      database = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)

      assert_equal %i[uuid int32 int16 uuid], database.column_types.columns(TablesFixtures::Refined).map(&:type)
    end

    it "opens up to pool: connections" do
      database = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), pool: 2, check: false)
      outer, inner = database.connection { |first| database.connection { |second| [first, second] } }

      refute_same outer, inner
    end

    # Its own process: other tests' table classes include ones whose declarations are invalid on purpose.
    it "checks every loaded table class against the schema" do
      script = <<~RUBY
        require "skyward/orm"

        class Note < Skyward::ORM::Record
          table :notes
          attr_reader :id
        end

        begin
          Skyward.connect(#{empty.url.inspect}, signatures: #{File.expand_path("missing", __dir__).inspect})
        rescue Skyward::ORM::SchemaMismatch => e
          puts e.message.lines.first
        end
      RUBY
      output, status = Open3.capture2e(Gem.ruby, "-e", script)

      assert_equal ["Note doesn't match the notes table\n", 0], [output, status.exitstatus]
    end

    it "connects with the check off inside the session's without_check" do
      database = Skyward::ORM::Connection::SESSION.without_check do
        Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"))
      end

      assert_same database, Skyward::ORM::Connection::SESSION.database
    end

    # Its own process too, for the same reason.
    it "checks a database it doesn't keep" do
      script = <<~RUBY
        require "skyward/orm"

        class Note < Skyward::ORM::Record
          table :notes
          attr_reader :id
        end

        begin
          Skyward.connect(#{empty.url.inspect}, signatures: #{File.expand_path("missing", __dir__).inspect}, default: false)
        rescue Skyward::ORM::SchemaMismatch => e
          puts e.message.lines.first
        end
      RUBY
      output, status = Open3.capture2e(Gem.ruby, "-e", script)

      assert_equal ["Note doesn't match the notes table\n", 0], [output, status.exitstatus]
    end

    # Its own process too, for the same reason.
    it "doesn't keep a database that doesn't match" do
      signatures = File.expand_path("missing", __dir__).inspect
      script = <<~RUBY
        require "skyward/orm"

        class Note < Skyward::ORM::Record
          table :notes
          attr_reader :id
        end

        kept = Skyward.connect(#{empty.url.inspect}, signatures: #{signatures}, check: false)
        begin
          Skyward.connect(#{empty.url.inspect}, signatures: #{signatures})
        rescue Skyward::ORM::SchemaMismatch
          p Skyward::ORM::Connection::SESSION.database.equal?(kept)
        end
      RUBY
      output, status = Open3.capture2e(Gem.ruby, "-e", script)

      assert_equal ["true\n", 0], [output, status.exitstatus]
    end

    it "returns a database without keeping it with default: false" do
      kept = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)
      database = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false, default: false)

      assert_equal [Skyward::ORM::Database, kept], [database.class, Skyward::ORM::Connection::SESSION.database]
    end

    describe "instrument:" do
      list = TablesFixtures::List

      let(:executions) { [] }
      let(:durations) { [] }
      let(:instrument) do
        lambda do |execution, &run|
          executions << execution
          durations << run.call
        end
      end
      let(:database) { Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false, instrument:) }
      # The SQL the adapter reads the schema with, which is the same whatever the schema holds.
      let(:schema_reads) { recorded { |connection| empty.adapter.tables(connection) } }

      def execution(sql, binds = []) = Skyward::ORM::Execution.new(sql:, binds:, adapter: empty.adapter.adapter_name)

      def recorded
        sent = []
        yield TestDatabase::Recording.new(connection: empty.connect, sent:)
        sent.map { |sql, binds| execution(sql, binds) }
      end

      def shown(sql, *values) = execution(*empty.shown(sql, values))

      def reported
        database.execute("CREATE TABLE lists (id #{empty.primary_key}, name TEXT NOT NULL UNIQUE)")
        executions.clear
        yield
        executions
      end

      it "refuses anything without call, before it connects" do
        error = assert_raises(Skyward::Core::BootError) { Skyward.connect("nowhere://", instrument: :log) }

        assert_equal "Skyward.connect's instrument: takes something that responds to call, such as a lambda, " \
                     "not a Symbol",
                     error.message
      end

      it "reports the schema reads at connect, each with its duration as a Float" do
        database

        assert_equal [schema_reads, [Float] * schema_reads.size], [executions, durations.map(&:class)]
      end

      it "reports a query, with its SQL and encoded binds" do
        query = list.where(id: 1, name: %w[Home Work])

        assert_equal([execution(*query.to_sql)], reported { query.to_a })
      end

      it "reports a write" do
        insert = shown(%(INSERT INTO "lists" ("name") VALUES (?)), "Home")

        assert_equal([insert], reported { list.insert(name: "Home") })
      end

      it "reports raw SQL" do
        sql = "SELECT name FROM lists WHERE id > ? AND name <> ?"

        assert_equal([shown(sql, 1, "Home")], reported { Skyward.query(sql, 1, "Home") })
      end

      it "reports a nested transaction's statements, in the order they're sent" do
        insert = shown(%(INSERT INTO "lists" ("name") VALUES (?)), "Home")
        sent = reported { Skyward.transaction { Skyward.transaction { list.insert(name: "Home") } } }

        assert_equal [
          execution("BEGIN"),
          execution("SAVEPOINT skyward_1"),
          insert,
          execution("RELEASE SAVEPOINT skyward_1"),
          execution("COMMIT")
        ],
                     sent
      end

      it "reports the transaction Skyward::ORM::Transactional holds for a test" do
        test = Class.new(Minitest::Spec) { define_method(:example) { list.insert(name: "Home") } }
        test.include(Skyward::ORM::Transactional)
        insert = shown(%(INSERT INTO "lists" ("name") VALUES (?)), "Home")

        assert_equal([execution("BEGIN"), insert, execution("ROLLBACK")], reported { test.new(:example).run })
      end

      it "reports a migration, its bookkeeping and the schema read after it, with no empty statement" do
        migration = Skyward::ORM::Migrations::Runner.parse(
          "20261001000000_create_notes.sql",
          "CREATE TABLE notes (id INTEGER);\n"
        )
        adapter = empty.adapter
        foreign_key_check = recorded { |connection| adapter.foreign_key_violations(connection) }
        lock = execution(adapter.begin_migration)
        unlock = [adapter.end_migration].compact.map { |sql| execution(sql) }
        create = "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, checksum TEXT NOT NULL, " \
                 "ran_at #{adapter.sql_type(:time)} NOT NULL DEFAULT CURRENT_TIMESTAMP)"
        pending = shown("SELECT 1 FROM schema_migrations WHERE version = ?", migration.version)
        record = shown(
          "INSERT INTO schema_migrations (version, checksum) VALUES (?, ?)",
          migration.version,
          migration.checksum
        )

        assert_equal(
          [
            *schema_reads,
            lock, execution(create), execution("COMMIT"), *unlock,
            execution("SELECT version, checksum FROM schema_migrations"),
            lock, pending, execution(migration.up), *foreign_key_check, record, execution("COMMIT"), *unlock,
            *schema_reads
          ],
          reported { database.migrate([migration]) }
        )
      end

      it "still returns a violation for a constraint the database refuses" do
        refused = nil
        sent = reported do
          list.insert(name: "Home")
          refused = list.insert(name: "Home")
        end

        assert_equal [Skyward::ORM::Violation, :unique, 2], [refused.class, refused.kind, sent.size]
      end

      it "leaves the pool's connections the adapter's own without it" do
        plain = Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false, default: false)

        assert_equal [empty.connect.class, Skyward::ORM::Connection::Instrumented],
                     [plain.connection(&:class), database.connection(&:class)]
      end
    end
  end

  describe ".using" do
    list = TablesFixtures::List

    let(:second) { TestDatabase.empty(second: true) }
    let(:switched) { Skyward.connect(second.url, signatures: File.join(fixtures, "sig"), check: false, default: false) }

    before do
      Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)
      create = "CREATE TABLE lists (id #{empty.primary_key}, name TEXT NOT NULL)"
      Skyward.query(create)
      switched.execute(create)
    end

    it "runs the block's queries, writes and raw SQL on the database, and returns the block's value" do
      read = Skyward.using(switched) do
        list.insert(name: "Work")
        [list.all.map(&:name), Skyward.query("SELECT name FROM lists")]
      end

      assert_equal [[["Work"], [{ name: "Work" }]], []], [read, Skyward.query("SELECT name FROM lists")]
    end

    it "runs a query built outside the block on the database current when it runs" do
      query = list.all
      Skyward.using(switched) { list.insert(name: "Work") }

      assert_equal [["Work"], []], [Skyward.using(switched) { query.map(&:name) }, query.map(&:name)]
    end

    it "opens transactions on the database, apart from one around the block" do
      seen = Skyward.transaction do
        inside = Skyward.using(switched) { [Skyward.transaction?, Skyward.transaction { Skyward.transaction? }] }
        [inside, Skyward.transaction?]
      end

      assert_equal [[false, true], true], seen
    end

    it "keeps the database's writes when a transaction around the block rolls back" do
      assert_raises(IOError) do
        Skyward.transaction do
          Skyward.using(switched) { list.insert(name: "Work") }
          list.insert(name: "Home")
          raise IOError
        end
      end

      assert_equal [["Work"], []], [Skyward.using(switched) { list.all.map(&:name) }, list.all.map(&:name)]
    end

    # Its own process, so no table class is loaded for the migration's check to compare.
    it "migrates the database" do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "20261001000000_create_notes.sql"), "CREATE TABLE notes (id INTEGER);\n")
        script = <<~RUBY
          require "skyward/orm"

          Skyward.connect(#{empty.url.inspect}, signatures: #{directory.inspect}, check: false)
          switched = Skyward.connect(#{second.url.inspect}, signatures: #{directory.inspect}, check: false, default: false)
          p Skyward.using(switched) { Skyward.migrate(#{directory.inspect}) }, Skyward.migrate(#{directory.inspect})
        RUBY
        output, status = Open3.capture2e(Gem.ruby, "-e", script)

        assert_equal [%(["20261001000000"]\n["20261001000000"]\n), 0], [output, status.exitstatus]
      end
    end

    it "refuses anything but a database" do
      error = assert_raises(ArgumentError) { Skyward.using(second.url) { nil } }

      assert_equal "Skyward.using takes a database Skyward.connect returned, not a String", error.message
    end

    it "refuses no block" do
      error = assert_raises(ArgumentError) { Skyward.using(switched) }

      assert_equal "Skyward.using takes a block to run on the database", error.message
    end
  end

  describe ".transaction" do
    it "runs the block in a transaction on the connected database" do
      Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)

      assert(Skyward.transaction { Skyward.transaction? })
    end
  end

  describe ".transaction?" do
    it "is false outside a transaction on the connected database" do
      Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)

      refute_predicate Skyward, :transaction?
    end
  end

  describe ".query" do
    before do
      Skyward.connect(empty.url, signatures: File.join(fixtures, "sig"), check: false)
      due_on, done = %i[date bool].map { |type| empty.adapter.sql_type(type) }
      Skyward.query("CREATE TABLE todos (title TEXT NOT NULL, due_on #{due_on}, done #{done} NOT NULL)")
      Skyward.query("INSERT INTO todos VALUES (?, ?, ?)", "Milk", Date.new(2026, 10, 1), false)
      Skyward.query("INSERT INTO todos VALUES (?, ?, ?)", "Eggs", Date.today + 1, false)
    end

    it "returns symbol-keyed hashes when the SQL comes first" do
      assert_equal [{ title: "Milk" }], Skyward.query("SELECT title FROM todos WHERE due_on < ?", Date.today)
    end

    it "returns the README's Overdue rows, with days_late an Integer" do
      rows = Skyward.query(TablesFixtures::Overdue, <<~SQL, Date.today)
        SELECT title, current_date - due_on AS days_late
        FROM todos
        WHERE due_on < ? AND NOT done
        ORDER BY days_late DESC
      SQL

      assert_equal(
        [[TablesFixtures::Overdue, "Milk", Integer]],
        rows.map { |row| [row.class, row.title, row.days_late.class] }
      )
    end

    it "refuses anything else first" do
      error = assert_raises(ArgumentError) { Skyward.query(:todos, "SELECT 1") }

      assert_equal "Skyward.query takes a row class or the SQL as its first argument", error.message
    end
  end

  describe ".migrate" do
    # Its own process, so the only table class loaded is the one the migration makes a table for.
    it "runs the directory's pending migrations, then checks the loaded table classes against them" do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "20261001000000_create_notes.sql"), "CREATE TABLE notes (id INTEGER);\n")
        script = <<~RUBY
          require "skyward/orm"

          class Note < Skyward::ORM::Record
            table :notes
            attr_reader :id
          end

          Skyward.connect(#{empty.url.inspect}, signatures: #{directory.inspect}, check: false)
          p Skyward.migrate(#{directory.inspect}), Skyward.migrate(#{directory.inspect})
        RUBY
        output, status = Open3.capture2e(Gem.ruby, "-e", script)

        assert_equal [%(["20261001000000"]\n[]\n), 0], [output, status.exitstatus]
      end
    end

    # Its own process too: other tests' table classes include ones whose declarations are invalid on purpose.
    it "raises SchemaMismatch for a table class that doesn't match once it has migrated, even with nothing pending" do
      Dir.mktmpdir do |directory|
        script = <<~RUBY
          require "skyward/orm"

          class Note < Skyward::ORM::Record
            table :notes
            attr_reader :id
          end

          Skyward.connect(#{empty.url.inspect}, signatures: #{directory.inspect}, check: false)
          begin
            Skyward.migrate(#{directory.inspect})
          rescue Skyward::ORM::SchemaMismatch => e
            puts e.message.lines.first
          end
        RUBY
        output, status = Open3.capture2e(Gem.ruby, "-e", script)

        assert_equal ["Note doesn't match the notes table\n", 0], [output, status.exitstatus]
      end
    end

    it "raises what went wrong when it can't migrate" do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "20261001000000_broken.sql"), "INSERT INTO nowhere VALUES (1);\n")
        Skyward.connect(empty.url, signatures: File.expand_path("missing", __dir__), check: false)
        error = assert_raises(Skyward::ORM::MigrationError) { Skyward.migrate(directory) }

        assert_equal Skyward::ORM::Migrations::Runner.message(
          Skyward::ORM::Migrations::Runner::Failed.new(
            file: "20261001000000_broken.sql",
            message: empty.error("INSERT INTO nowhere VALUES (1);\n")
          )
        ),
                     error.message
      end
    end
  end

  describe ".sql" do
    it "wraps an SQL expression" do
      assert_equal Skyward::ORM::Tables::SQL.new(expression: "now()"), Skyward.sql("now()")
    end

    it "keeps a frozen copy" do
      assert_predicate Skyward.sql(+"now()").expression, :frozen?
    end

    it "refuses anything but a String" do
      error = assert_raises(ArgumentError) { Skyward.sql(:now) }

      assert_equal "Skyward.sql takes the SQL as a String, not :now", error.message
    end
  end
end
