# frozen_string_literal: true

require "digest"

module Skyward::ORM::Migrations::Runner
  extend self

  # @rbs!
  #   type outcome = Array[String] | Edited | Locked | Failed
  #   type unrolled = :nothing | Missing | Irreversible | Raced | Locked | Failed
  #   type rolled_back = String | unrolled

  TABLE = Skyward::ORM::Migrations::Versions::TABLE #: Symbol

  DOWN = /^[ \t]*-- down[ \t]*$/ #: Regexp

  RAN_AT = Skyward::ORM::Tables::Column.new(
    name: :ran_at, type: :time, nullable: false, symbols: [], element: nil
  ) #: Skyward::ORM::Tables::Column

  # @rbs path: String
  # @rbs return: Array[Migration]
  def read(path)
    Skyward::ORM::Migrations::Directory.sql_files(path).map do |file|
      parse(file, File.read(File.join(path, file)))
    end
  end

  # Line endings are normalised first, so a checkout that converts them
  # doesn't read as an edit.
  # @rbs file: String
  # @rbs source: String
  # @rbs return: Migration
  def parse(file, source)
    up, _, down = source.gsub("\r\n", "\n").partition(DOWN)
    Migration.new(
      file:,
      version: Skyward::ORM::Migrations::Directory.version(file),
      up:,
      down:,
      checksum: Digest::SHA256.hexdigest(up)
    )
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Array[Migration] migrations) -> outcome
  def run(adapter, connection, migrations)
    # Only when it's missing: on SQLite, even committing nothing under the
    # migration lock fails while another connection reads.
    refused = create_table(adapter, connection) unless adapter.tables(connection).any? { |table| table.name == TABLE }
    if refused
      return migrations.empty? ? [] : Locked.new(file: migrations.fetch(0).file, message: refused)
    end

    ran = connection.execute("SELECT version, checksum FROM #{TABLE}").to_h
    # A migration that ran but whose file is gone doesn't stop the rest, so old
    # migrations can be squashed.
    changed = migrations.reject { |migration| ran.fetch(migration.version, migration.checksum) == migration.checksum }
    return Edited.new(files: changed.map(&:file)) unless changed.empty?

    none = [] #: Array[String]
    migrations.reject { |migration| ran.key?(migration.version) }.reduce(none) do |versions, migration|
      applied = apply(adapter, connection, migration) do
        # Another migrator can run it between reading what has run and taking
        # the lock, so it's checked again now the lock is held.
        pending?(adapter, connection, migration) && change(adapter, connection, migration, migration.up) do
          connection.execute(
            "INSERT INTO #{TABLE} (version, checksum) VALUES (#{adapter.placeholder(1)}, #{adapter.placeholder(2)})",
            [migration.version, migration.checksum]
          )
        end
      end
      case applied
      when Locked, Failed then return applied
      when true then [*versions, migration.version]
      else versions
      end
    end
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Array[Migration] migrations)
  #   -> rolled_back
  def rollback(adapter, connection, migrations)
    version = latest(connection) if adapter.tables(connection).any? { |table| table.name == TABLE }
    return :nothing unless version

    migration = migrations.find { |candidate| candidate.version == version }
    return Missing.new(version:) unless migration
    return Irreversible.new(file: migration.file) if migration.down.strip.empty?

    undone = apply(adapter, connection, migration) do
      # Another migrator can run or roll back one between reading the latest
      # and taking the lock, so it's read again now the lock is held.
      latest(connection) == version && change(adapter, connection, migration, migration.down) do
        connection.execute("DELETE FROM #{TABLE} WHERE version = #{adapter.placeholder(1)}", [version])
      end
    end
    case undone
    when Locked, Failed then undone
    when true then version
    else Raced.new(file: migration.file)
    end
  end

  # @rbs failure: Edited | Locked | Failed
  # @rbs return: String
  def message(failure)
    case failure
    when Edited
      files = failure.files.map { |file| "  #{file}\n" }.join
      "These migrations changed after they ran, so none ran:\n#{files}" \
        "Put each back as it was, and make the change in a new migration. Only a -- down section can change."
    when Locked
      "#{failure.file} couldn't take the migration lock, which another migrator may hold, so neither it nor any " \
      "later migration ran: #{failure.message}"
    else "#{failure.file} failed, so it was rolled back and no later migration ran: #{failure.message}"
    end
  end

  # @rbs failure: unrolled
  # @rbs return: String
  def rollback_message(failure)
    case failure
    when :nothing then "No migration has run, so there's nothing to roll back."
    when Missing
      "#{failure.version} is the latest migration to have run, but its file is gone, so it can't be rolled back. " \
      "Put its file back to roll it back."
    when Irreversible
      "#{failure.file} has nothing in its -- down section, so it wasn't rolled back. " \
      "Write the SQL that undoes it there."
    when Raced
      "#{failure.file} isn't the latest migration anymore, since another migrator ran or rolled back one while " \
      "this one waited for the lock, so it wasn't rolled back."
    when Locked
      "#{failure.file} couldn't take the migration lock, which another migrator may hold, so it wasn't rolled back: " \
      "#{failure.message}"
    else "Rolling back #{failure.file} failed, so its -- down section was undone and it still counts as run: " \
         "#{failure.message}"
    end
  end

  private

  # Made under the migration lock, since two migrators making it at once on
  # PostgreSQL can collide in its catalog, and IF NOT EXISTS doesn't stop that.
  # Returns the database's message when the lock can't be taken.
  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection) -> String?
  def create_table(adapter, connection)
    connection.execute_batch(adapter.begin_migration)
  rescue StandardError => e
    cancel(connection)
    e.message
  else
    settled = false
    begin
      connection.execute(
        "CREATE TABLE IF NOT EXISTS #{TABLE} (version TEXT PRIMARY KEY, checksum TEXT NOT NULL, " \
        "ran_at #{adapter.sql_type(RAN_AT)} NOT NULL DEFAULT CURRENT_TIMESTAMP)"
      )
      connection.execute("COMMIT")
      settled = true
    ensure
      cancel(connection) unless settled
    end
    nil
  ensure
    end_migration(adapter, connection)
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration)
  #   { () -> (bool | Failed) } -> (bool | Locked | Failed)
  def apply(adapter, connection, migration, &)
    connection.execute_batch(adapter.begin_migration)
  rescue StandardError => e
    # PostgreSQL leaves the transaction open when the lock is what failed.
    cancel(connection)
    Locked.new(file: migration.file, message: e.message)
  else
    run_locked(connection, migration, &)
  ensure
    end_migration(adapter, connection)
  end

  # Rolled back in ensure rather than rescue, so a migration left by throw or a
  # killed thread rolls back too, before foreign keys go back on.
  # @rbs (Skyward::ORM::_Connection connection, Migration migration) { () -> (bool | Failed) } -> (bool | Failed)
  def run_locked(connection, migration)
    settled = false
    begin
      applied = yield
      connection.execute(applied.is_a?(Failed) ? "ROLLBACK" : "COMMIT")
      settled = true
      applied
    rescue StandardError => e
      Failed.new(file: migration.file, message: e.message)
    ensure
      cancel(connection) unless settled
    end
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection) -> void
  def end_migration(adapter, connection)
    sql = adapter.end_migration
    connection.execute_batch(sql) if sql
  end

  # SQLite ends the transaction itself on some failures, such as ON CONFLICT
  # ROLLBACK, and then ROLLBACK raises, though the outcome is already decided.
  # @rbs (Skyward::ORM::_Connection connection) -> void
  def cancel(connection)
    connection.execute("ROLLBACK")
  rescue StandardError
    nil
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration) -> bool
  def pending?(adapter, connection, migration)
    connection.execute("SELECT 1 FROM #{TABLE} WHERE version = #{adapter.placeholder(1)}", [migration.version]).empty?
  end

  # Versions sort in filename order, which is the order they ran in, so the
  # greatest is the latest.
  # @rbs (Skyward::ORM::_Connection connection) -> String?
  def latest(connection) = connection.execute("SELECT max(version) FROM #{TABLE}").dig(0, 0)

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration, String section)
  #   { () -> void } -> (true | Failed)
  def change(adapter, connection, migration, section)
    connection.execute_batch(section)
    violations = adapter.foreign_key_violations(connection)
    if violations.any?
      return Failed.new(file: migration.file, message: "foreign key check failed: #{violations.join(", ")}")
    end

    yield
    true
  end
end
