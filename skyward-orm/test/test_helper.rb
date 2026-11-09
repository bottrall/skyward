# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "skyward/orm"
require "tmpdir"

# The database the suite's tests of behaviour every database shares run on.
# TEST_DATABASE picks it: sqlite, the default, or postgresql, at
# TEST_POSTGRES_URL. The PostgreSQL adapter's own tests always use that URL,
# and the SQLite adapter's always use SQLite, so every run runs every test.
module TestDatabase
  extend self

  # An empty database's URL and adapter. Every connection to it opens the
  # same database, so a test can pool more than one.
  Empty = Data.define(:url, :adapter, :location) do
    def connect = adapter.connect(location)

    def primary_key = [adapter.sql_type(:integer), adapter.identity, "PRIMARY KEY"].compact.join(" ")

    # The database's message for SQL that fails, and changes nothing.
    def error(sql)
      connect.execute_batch(sql)
    rescue StandardError => e
      e.message
    end

    # The violation the adapter reads from the database's error for SQL that
    # breaks a constraint on the table, and changes nothing.
    def violation(sql, table)
      connection = connect
      connection.execute_batch(sql)
    rescue StandardError => e
      adapter.violation(e, adapter.tables(connection), table)
    end

    def violated(expected, sql, table) = expected.with(message: violation(sql, table)&.message)

    # Numbered as PostgreSQL's are, so each one's position shows on every database.
    def numbered
      numbering = adapter
      Module.new do
        extend numbering

        def self.placeholder(position) = "$#{position}"
      end
    end

    # The SQL and binds a statement shows on this database: each ? as the
    # adapter's placeholder, and each value as the adapter encodes it.
    def shown(sql, values)
      numbered = sql.gsub("?").with_index(1) { |_, position| adapter.placeholder(position) }
      [numbered, values.map { |value| adapter.encode(value) }]
    end
  end

  Recording = Data.define(:connection, :sent) do
    def execute(sql, binds = [])
      sent << [sql, binds]
      connection.execute(sql, binds)
    end
  end

  DIRECTORY = Dir.mktmpdir("skyward-orm-test")
  Minitest.after_run { FileUtils.rm_rf(DIRECTORY) }

  # The connections earlier tests left open are closed first, so none holds a
  # lock the drop waits on, or counts against max_connections.
  RESET = <<~SQL
    SET client_min_messages = warning;
    SELECT pg_terminate_backend(pid) FROM pg_stat_activity
    WHERE datname = current_database() AND pid <> pg_backend_pid();
    DROP SCHEMA IF EXISTS public CASCADE;
    CREATE SCHEMA public;
  SQL

  def empty(kind = ENV.fetch("TEST_DATABASE", "sqlite"))
    url = case kind
          when "sqlite" then "sqlite://#{File.join(Dir.mktmpdir(nil, DIRECTORY), "test.db")}"
          when "postgresql" then reset(postgres_url)
          else raise ArgumentError, "TEST_DATABASE is sqlite or postgresql, not #{kind.inspect}"
          end
    adapter, location = Skyward::ORM::Adapters.resolve(
      url,
      schemes: Skyward::ORM::Adapters::SCHEMES,
      requirer: ->(feature) { require feature }
    )
    Empty.new(url:, adapter:, location:)
  end

  private

  def postgres_url
    ENV.fetch("TEST_POSTGRES_URL") do
      raise "Set TEST_POSTGRES_URL to a PostgreSQL database the tests can empty. CONTRIBUTING.md says how."
    end
  end

  def reset(url)
    require "pg"
    connection = PG.connect(url)
    connection.exec(RESET)
    url
  ensure
    connection&.close
  end
end
