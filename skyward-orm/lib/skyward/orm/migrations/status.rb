# frozen_string_literal: true

module Skyward::ORM::Migrations::Status
  extend self

  # @rbs!
  #   type state = :ran | :pending | :edited | :gone

  STATES = {
    ran: "ran",
    pending: "pending",
    edited: "edited after it ran",
    gone: "ran, but its file is gone"
  }.freeze #: Hash[state, String]

  NONE = "No migrations yet.\n" #: String

  CLEAN = "Nothing is pending, and every table matches its class.\n" #: String

  # A migration whose file is gone is named by its version, which is all the
  # database keeps of its name, and sorts among the files as it did.
  # @rbs migrations: Array[Skyward::ORM::Migrations::Runner::Migration]
  # @rbs ran: Hash[String, String]
  # @rbs return: Array[[String, state]]
  def migrations(migrations, ran)
    files = migrations.map do |migration|
      [migration.file, state(migration, ran[migration.version])] #: [String, state]
    end
    gone = (ran.keys - migrations.map(&:version)).map do |version|
      [version, :gone] #: [String, state]
    end
    [*files, *gone].sort_by(&:first)
  end

  # schema_migrations is Skyward ORM's own, so it never needs a class.
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: Array[Symbol]
  def unowned(tables, classes)
    owned = [Skyward::ORM::Migrations::Versions::TABLE, *classes.map(&:table_name)]
    tables.map(&:name).reject { |name| owned.include?(name) }
  end

  # @rbs migrations: Array[[String, state]]
  # @rbs changes: Array[Skyward::ORM::Migrations::change]
  # @rbs unowned: Array[Symbol]
  # @rbs return: bool
  def clean?(migrations, changes, unowned)
    migrations.all? { |_, state| state == :ran } && changes.empty? && unowned.empty?
  end

  # @rbs (Array[[String, state]] migrations, Array[Skyward::ORM::Migrations::change] changes, Array[Symbol] unowned,
  #   Skyward::ORM::_Adapter adapter) -> String
  def text(migrations, changes, unowned, adapter)
    [
      listing(migrations),
      Skyward::ORM::Migrations::Summary.text(changes, adapter),
      unowned_text(unowned),
      clean?(migrations, changes, unowned) ? CLEAN : ""
    ].join
  end

  private

  # @rbs migration: Skyward::ORM::Migrations::Runner::Migration
  # @rbs checksum: String?
  # @rbs return: state
  def state(migration, checksum)
    case checksum
    when nil then :pending
    when migration.checksum then :ran
    else :edited
    end
  end

  # @rbs migrations: Array[[String, state]]
  # @rbs return: String
  def listing(migrations)
    return NONE if migrations.empty?

    width = migrations.map { |name, _| name.length }.max.to_i
    ["Migrations:\n", *migrations.map { |name, state| "  #{name.ljust(width)}  #{STATES.fetch(state)}\n" }].join
  end

  # @rbs unowned: Array[Symbol]
  # @rbs return: String
  def unowned_text(unowned)
    return "" if unowned.empty?

    ["These tables have no class, so `skyward migration` leaves them alone:\n",
     *unowned.map { |table| "  #{table}\n" }].join
  end
end
