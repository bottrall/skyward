# frozen_string_literal: true

require "digest"

module Skyward::ORM::Migrations::Runner
  extend self

  # @rbs!
  #   type outcome = Array[String] | Edited | Locked | Failed

  TABLE = Skyward::ORM::Migrations::Versions::TABLE #: Symbol

  DOWN = /^[ \t]*-- down[ \t]*$/ #: Regexp

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
    up = source.gsub("\r\n", "\n").partition(DOWN).first
    Migration.new(
      file:,
      version: Skyward::ORM::Migrations::Directory.version(file),
      up:,
      checksum: Digest::SHA256.hexdigest(up)
    )
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Array[Migration] migrations) -> outcome
  def run(adapter, connection, migrations)
    connection.execute(
      "CREATE TABLE IF NOT EXISTS #{TABLE} (version TEXT PRIMARY KEY, checksum TEXT NOT NULL, " \
      "ran_at #{adapter.sql_type(:time)} NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    )
    ran = connection.execute("SELECT version, checksum FROM #{TABLE}").to_h
    # A migration that ran but whose file is gone doesn't stop the rest, so old
    # migrations can be squashed.
    changed = migrations.reject { |migration| ran.fetch(migration.version, migration.checksum) == migration.checksum }
    return Edited.new(files: changed.map(&:file)) unless changed.empty?

    none = [] #: Array[String]
    migrations.reject { |migration| ran.key?(migration.version) }.reduce(none) do |versions, migration|
      applied = apply(adapter, connection, migration)
      case applied
      when Locked, Failed then return applied
      when true then [*versions, migration.version]
      else versions
      end
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

  private

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration)
  #   -> (bool | Locked | Failed)
  def apply(adapter, connection, migration)
    connection.execute_batch(adapter.begin_migration)
  rescue StandardError => e
    Locked.new(file: migration.file, message: e.message)
  else
    run_locked(adapter, connection, migration)
  ensure
    connection.execute_batch(adapter.end_migration)
  end

  # Rolled back in ensure rather than rescue, so a migration left by throw or a
  # killed thread rolls back too, before foreign keys go back on.
  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration) -> (bool | Failed)
  def run_locked(adapter, connection, migration)
    settled = false
    begin
      # Another migrator can run it between reading what has run and taking the
      # lock, so it's checked again now the lock is held.
      pending = connection.execute(
        "SELECT 1 FROM #{TABLE} WHERE version = #{adapter.placeholder(1)}",
        [migration.version]
      ).empty?
      applied = pending ? up(adapter, connection, migration) : false
      connection.execute(applied.is_a?(Failed) ? "ROLLBACK" : "COMMIT")
      settled = true
      applied
    rescue StandardError => e
      Failed.new(file: migration.file, message: e.message)
    ensure
      rollback(connection) unless settled
    end
  end

  # SQLite ends the transaction itself on some failures, such as ON CONFLICT
  # ROLLBACK, and then ROLLBACK raises, though the outcome is already decided.
  # @rbs (Skyward::ORM::_Connection connection) -> void
  def rollback(connection)
    connection.execute("ROLLBACK")
  rescue StandardError
    nil
  end

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection, Migration migration) -> (true | Failed)
  def up(adapter, connection, migration)
    connection.execute_batch(migration.up)
    violations = adapter.foreign_key_violations(connection)
    if violations.any?
      return Failed.new(file: migration.file, message: "foreign key check failed: #{violations.join(", ")}")
    end

    connection.execute(
      "INSERT INTO #{TABLE} (version, checksum) VALUES (#{adapter.placeholder(1)}, #{adapter.placeholder(2)})",
      [migration.version, migration.checksum]
    )
    true
  end
end
