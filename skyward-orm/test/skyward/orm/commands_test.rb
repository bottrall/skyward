# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'test_helper'
require 'tmpdir'

describe 'skyward/orm/commands.rb' do
  fixture = File.expand_path('../../fixtures/app', __dir__)

  let(:empty) { TestDatabase.empty }

  def skyward(*args, chdir:)
    env = { 'DATABASE_URL' => empty.url }
    output, status = Open3.capture2e(env, Gem.ruby, Gem.bin_path('skyward-core', 'skyward'), *args, chdir:)
    [output, status.exitstatus]
  end

  # A copy, so the database and migrations it writes go away with it.
  define_method(:app) do |&block|
    Dir.mktmpdir do |directory|
      FileUtils.cp_r("#{fixture}/.", directory)
      block.call(directory)
    end
  end

  describe 'migration' do
    it "writes the migration for the app's table classes, though nothing has loaded them" do
      app do |directory|
        output, status = skyward('migration', 'create_todos', chdir: directory)
        expected = <<~TEXT
          List has no table yet:
            + lists  2 columns
          Todo has no table yet:
            + todos  7 columns, 1 reference, 2 checks, 1 index
          Wrote db/migrate/TIMESTAMP_create_todos.sql. Review it, then run `skyward migrate`.
        TEXT

        assert_equal [expected, 0], [output.sub(/\d{14}/, 'TIMESTAMP'), status]
      end
    end

    it 'uses sig/ as it is, and says nothing about it, in a bundle without rbs-inline, as this one is' do
      app do |directory|
        File.write(File.join(directory, 'app/note.rb'), "# rbs_inline: enabled\n\nclass Note\nend\n")
        output, status = skyward('migration', 'create_todos', chdir: directory)

        assert_equal [0, false, false],
                     [status, output.include?('rbs-inline'), File.exist?(File.join(directory, 'sig/generated'))]
      end
    end

    it 'has nothing to write once that migration has run' do
      app do |directory|
        skyward('migration', 'create_todos', chdir: directory)
        skyward('migrate', chdir: directory)

        assert_equal ["Every table matches its class. Nothing to write.\n", 0],
                     skyward('migration', 'add_notes_to_todos', chdir: directory)
      end
    end

    it 'shows how to use it, and exits 1, without a name' do
      app do |directory|
        assert_equal ["#{Skyward::ORM::CLI::Migration::USAGE}\n", 1], skyward('migration', chdir: directory)
      end
    end
  end

  describe 'migrate' do
    it 'runs the migration skyward migration wrote, once' do
      app do |directory|
        skyward('migration', 'create_todos', chdir: directory)
        ran = [skyward('migrate', chdir: directory), skyward('migrate', chdir: directory)]

        assert_equal(
          [["Migrated TIMESTAMP\n", 0], ["No pending migrations.\n", 0]],
          ran.map { |output, status| [output.sub(/\d{14}/, 'TIMESTAMP'), status] }
        )
      end
    end

    it 'fails without a backtrace, and exits 1, when a migration fails' do
      app do |directory|
        FileUtils.mkdir_p(File.join(directory, 'db/migrate'))
        File.write(File.join(directory, 'db/migrate/20261001000000_broken.sql'), "INSERT INTO nowhere VALUES (1);\n")

        message = '20261001000000_broken.sql failed, so it was rolled back and no later migration ran: ' \
                  "#{empty.error("INSERT INTO nowhere VALUES (1);\n")}"

        # abort ends the line, unless the message already does.
        assert_equal ["#{message.chomp}\n", 1], skyward('migrate', chdir: directory)
      end
    end
  end

  describe 'rollback' do
    def schema = empty.adapter.tables(empty.connect).reject { |table| table.name == :schema_migrations }

    it 'undoes the migration skyward migration wrote, so migrating again makes the same schema' do
      app do |directory|
        skyward('migration', 'create_todos', chdir: directory)
        skyward('migrate', chdir: directory)
        migrated = schema
        output, status = skyward('rollback', chdir: directory)
        rolled_back = schema
        skyward('migrate', chdir: directory)

        assert_equal [["Rolled back TIMESTAMP\n", 0], [], migrated],
                     [[output.sub(/\d{14}/, 'TIMESTAMP'), status], rolled_back, schema]
      end
    end

    it 'fails without a backtrace, and exits 1, when nothing has run' do
      app do |directory|
        assert_equal ["No migration has run, so there's nothing to roll back.\n", 1],
                     skyward('rollback', chdir: directory)
      end
    end
  end

  describe 'status' do
    it "exits 1 while a migration is pending, and 0 once it's run" do
      app do |directory|
        skyward('migration', 'create_todos', chdir: directory)
        pending = skyward('status', chdir: directory)
        skyward('migrate', chdir: directory)
        clean = skyward('status', chdir: directory)

        assert_equal(
          [
            [
              "Migrations:\n  TIMESTAMP_create_todos.sql  pending\n" \
              "List has no table yet:\n  + lists  2 columns\n" \
              "Todo has no table yet:\n  + todos  7 columns, 1 reference, 2 checks, 1 index\n",
              1
            ],
            ["Migrations:\n  TIMESTAMP_create_todos.sql  ran\n#{Skyward::ORM::Migrations::Status::CLEAN}", 0]
          ],
          [pending, clean].map { |output, status| [output.gsub(/\d{14}/, 'TIMESTAMP'), status] }
        )
      end
    end
  end

  describe 'scaffold' do
    nothing = ["Every table matches its class. Nothing to write.\n", 0]

    # rbs-inline isn't in this bundle, so the class's signature is written from
    # its #: comments, as rbs-inline would write it.
    def signature(source)
      uses = source.scan(/^# @rbs (use .*)$/).map { |(use)| "#{use}\n" }
      readers = source.scan(/^  attr_reader :(\w+) +#: (.*)$/).map { |name, type| "  attr_reader #{name}: #{type}\n" }
      [*uses, "class #{source[/^class (\w+)/, 1]} < ::Skyward::ORM::Record\n", *readers, "end\n"].join
    end

    # Todo's class goes, and the scaffolded one takes its place.
    def replace_todo(directory)
      File.delete(File.join(directory, 'app/todo.rb'))
      app_rbs = File.join(directory, 'sig/app.rbs')
      File.write(app_rbs, File.read(app_rbs)[/\Aclass List\b.*?^end\n/m])
      output, status = skyward('scaffold', 'todos', chdir: directory)
      File.write(File.join(directory, 'app/todo.rb'), output)
      File.write(File.join(directory, 'sig/todo.rbs'), signature(output))
      status
    end

    it 'prints a class that leaves skyward migration nothing to write, and skyward status nothing to report, for a ' \
       'table a generated migration created' do
      app do |directory|
        skyward('migration', 'create_todos', chdir: directory)
        skyward('migrate', chdir: directory)

        assert_equal [0, nothing, 0],
                     [replace_todo(directory), skyward('migration', 'again', chdir: directory),
                      skyward('status', chdir: directory).last]
      end
    end

    it 'prints a class that leaves skyward migration nothing to write, and skyward status nothing to report, for a ' \
       "table written by hand, with PostgreSQL's default constraint names" do
      app do |directory|
        adapter = empty.adapter
        integer, text, date, bool, time = %i[integer string date bool time].map do |type|
          adapter.sql_type(TestDatabase.column(type))
        end
        FileUtils.mkdir_p(File.join(directory, 'db/migrate'))
        File.write(File.join(directory, 'db/migrate/20261001000000_by_hand.sql'), <<~SQL)
          CREATE TABLE lists (id #{empty.primary_key}, name #{text} NOT NULL);
          CREATE TABLE todos (
            id #{empty.primary_key},
            list_id #{integer} NOT NULL REFERENCES lists ON DELETE CASCADE,
            title #{text} NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
            priority #{text} NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
            due_on #{date},
            done #{bool} NOT NULL DEFAULT #{Skyward::ORM::Migrations::Definitions.literal(adapter.encode(false))},
            created_at #{time} NOT NULL DEFAULT CURRENT_TIMESTAMP
          );
          CREATE INDEX todos_list_id_done_idx ON todos (list_id, done);
        SQL
        skyward('migrate', chdir: directory)

        assert_equal [0, nothing, 0],
                     [replace_todo(directory), skyward('migration', 'again', chdir: directory),
                      skyward('status', chdir: directory).last]
      end
    end

    describe 'on PostgreSQL' do
      let(:empty) { TestDatabase.empty('postgresql') }

      it 'prints a jsonb column, with and without a default, as Hash[String, untyped], and then has nothing to write' do
        app do |directory|
          FileUtils.mkdir_p(File.join(directory, 'db/migrate'))
          File.write(File.join(directory, 'db/migrate/20261001000000_by_hand.sql'), <<~SQL)
            CREATE TABLE lists (id #{empty.primary_key}, name text NOT NULL);
            CREATE TABLE todos (
              id #{empty.primary_key},
              meta jsonb NOT NULL DEFAULT '{"a":1}',
              payload jsonb,
              extra json
            );
          SQL
          skyward('migrate', chdir: directory)
          replace_todo(directory)
          types = File.read(File.join(directory, 'app/todo.rb')).scan(/^  attr_reader :\w+ +#: (.*)$/).flatten

          assert_equal [['Integer', 'Hash[String, untyped]', *['Hash[String, untyped]?'] * 2], nothing],
                       [types, skyward('migration', 'again', chdir: directory)]
        end
      end
    end

    describe 'on SQLite' do
      let(:empty) { TestDatabase.empty('sqlite') }

      it 'prints a class whose defaults skyward migration rewrites once, where no value writes one back as SQLite ' \
         'keeps it, and then has nothing to write' do
        app do |directory|
          FileUtils.mkdir_p(File.join(directory, 'db/migrate'))
          File.write(File.join(directory, 'db/migrate/20261001000000_by_hand.sql'), <<~SQL)
            CREATE TABLE lists (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE todos (
              id INTEGER PRIMARY KEY,
              estimate NUMERIC NOT NULL DEFAULT (1.50),
              done BOOLEAN NOT NULL DEFAULT TRUE,
              created_at DATETIME NOT NULL DEFAULT '2026-01-02 03:04:05'
            );
          SQL
          skyward('migrate', chdir: directory)
          replace_todo(directory)
          output, status = skyward('migration', 'rewrite_defaults', chdir: directory)
          skyward('migrate', chdir: directory)
          rewritten = <<~TEXT
            Todo differs from the todos table:
              ~ estimate    DEFAULT 1.5, was DEFAULT 1.50
              ~ done        DEFAULT 1, was DEFAULT TRUE
              ~ created_at  DEFAULT '2026-01-02 03:04:05.000000', was DEFAULT '2026-01-02 03:04:05'
            Wrote db/migrate/TIMESTAMP_rewrite_defaults.sql. Review it, then run `skyward migrate`.
          TEXT

          assert_equal [[rewritten, 0], nothing],
                       [[output.sub(/\d{14}/, 'TIMESTAMP'), status], skyward('migration', 'again', chdir: directory)]
        end
      end
    end

    it 'shows how to use it, and exits 1, without a table' do
      app do |directory|
        assert_equal ["#{Skyward::ORM::CLI::Scaffold::USAGE}\n", 1], skyward('scaffold', chdir: directory)
      end
    end
  end
end
