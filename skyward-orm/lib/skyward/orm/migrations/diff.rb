# frozen_string_literal: true

module Skyward::ORM::Migrations::Diff
  extend self

  # New tables come first, each after the tables it references, so a new
  # column can reference a new table too.
  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs return: Array[Skyward::ORM::Migrations::change]
  def changes(classes, column_types, tables)
    classes.each { |klass| Skyward::ORM::Tables::Validation.validate(klass) }
    refuse_shared(classes)
    existing = tables.to_h { |table| [table.name, table] }
    sorted = classes.sort_by { |klass| klass.table_name.name }
    created = sorted.reject { |klass| existing.key?(klass.table_name) }.map do |klass|
      Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))
    end
    added = sorted.filter_map do |klass|
      table = existing[klass.table_name]
      added(klass, column_types.columns(klass), table) if table
    end
    [*parents_first(created), *added]
  end

  private

  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: void
  def refuse_shared(classes)
    shared = classes.group_by(&:table_name).select { |_, owners| owners.size > 1 }
    return if shared.empty?

    problems = shared.map do |table, owners|
      "#{owners.map(&:to_s).sort.join(" and ")} each declare table :#{table}. Give each table one class."
    end
    raise Skyward::Core::BootError, problems.join("\n")
  end

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs columns: Array[Skyward::ORM::Tables::Column]
  # @rbs table: Skyward::ORM::Catalog::Table
  # @rbs return: Skyward::ORM::Migrations::AddColumns?
  def added(klass, columns, table)
    names = table.columns.map(&:name)
    missing = columns.reject { |column| names.include?(column.name) }
    Skyward::ORM::Migrations::AddColumns.new(klass:, columns: missing) unless missing.empty?
  end

  # Tables that reference each other can't all come after their parents, so
  # the first left goes next.
  # @rbs pending: Array[Skyward::ORM::Migrations::CreateTable]
  # @rbs placed: Array[Skyward::ORM::Migrations::CreateTable]
  # @rbs return: Array[Skyward::ORM::Migrations::CreateTable]
  def parents_first(pending, placed = [])
    return placed if pending.empty?

    waiting = pending.map { |change| change.klass.table_name }
    ready = pending.find do |change|
      parents(change.klass).none? { |parent| parent != change.klass.table_name && waiting.include?(parent) }
    end
    following = ready || pending.fetch(0)
    parents_first(pending - [following], [*placed, following])
  end

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: Array[Symbol]
  def parents(klass) = klass.schema.references.map { |reference| reference.table.table_name }
end
