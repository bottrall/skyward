# frozen_string_literal: true

module Skyward::ORM::Migrations::Diff
  extend self

  ON_DELETE = /\bON\s+DELETE\s+(CASCADE|RESTRICT|SET\s+NULL|SET\s+DEFAULT|NO\s+ACTION)\b/i #: Regexp

  # New tables come first, each after the tables it references, so a changed
  # table can reference a new table too. A table with no class is left alone:
  # a class that isn't loaded looks the same.
  # @rbs (Array[singleton(Skyward::ORM::Record)] classes, Skyward::ORM::Tables::ColumnTypes column_types,
  #   Array[Skyward::ORM::Catalog::Table] tables, Skyward::ORM::_Adapter adapter,
  #   ^(Symbol table, Symbol from, Symbol to) -> bool rename) -> Array[Skyward::ORM::Migrations::change]
  def changes(classes, column_types, tables, adapter, rename)
    classes.each { |klass| Skyward::ORM::Tables::Validation.validate(klass) }
    refuse_shared(classes)
    existing = tables.to_h { |table| [table.name, table] }
    sorted = classes.sort_by { |klass| klass.table_name.name }
    created = sorted.reject { |klass| existing.key?(klass.table_name) }.map do |klass|
      Skyward::ORM::Migrations::CreateTable.new(klass:, columns: column_types.columns(klass))
    end
    altered = sorted.filter_map do |klass|
      table = existing[klass.table_name]
      altered(klass, column_types.columns(klass), table, adapter, rename) if table
    end
    [*parents_first(created), *altered]
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

  # Indexes and constraints go before the columns they're on, and come back
  # after the columns they need.
  # @rbs (singleton(Skyward::ORM::Record) klass, Array[Skyward::ORM::Tables::Column] columns,
  #   Skyward::ORM::Catalog::Table table, Skyward::ORM::_Adapter adapter,
  #   ^(Symbol table, Symbol from, Symbol to) -> bool rename) -> Skyward::ORM::Migrations::AlterTable?
  def altered(klass, columns, table, adapter, rename)
    names = columns.map(&:name)
    had = table.columns.map(&:name)
    added = columns.reject { |column| had.include?(column.name) }
    removed = table.columns.reject { |column| names.include?(column.name) }
    renamed = renames(klass.table_name, removed, added, adapter, rename)
    new_columns = added.reject { |column| renamed.value?(column.name) }
    dropped_indexes, added_indexes = indexes(klass, table, renamed)
    dropped_constraints, added_constraints = constraints(klass, columns, table, renamed, new_columns)
    dropped_columns = removed.reject { |column| renamed.key?(column.name) }
    edits = [
      *dropped_indexes,
      *dropped_constraints,
      *dropped_columns.map { |column| Skyward::ORM::Migrations::DropColumn.new(column:) },
      *renamed.map { |from, to| Skyward::ORM::Migrations::RenameColumn.new(from:, to:) },
      *new_columns.map { |column| Skyward::ORM::Migrations::AddColumn.new(column:) },
      *columns.flat_map do |column|
        found = table.columns.find { |kept| renamed.fetch(kept.name, kept.name) == column.name }
        found ? changed(klass, column, found, adapter) : []
      end,
      *added_constraints,
      *added_indexes
    ] #: Array[Skyward::ORM::Migrations::edit]
    Skyward::ORM::Migrations::AlterTable.new(klass:, columns:, table:, edits:) unless edits.empty?
  end

  # The indexes to drop and to add. One is compared by the columns it will
  # have after any rename, and dropped as the database has it.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs table: Skyward::ORM::Catalog::Table
  # @rbs renamed: Hash[Symbol, Symbol]
  # @rbs return: [Array[Skyward::ORM::Migrations::edit], Array[Skyward::ORM::Migrations::edit]]
  def indexes(klass, table, renamed)
    wanted = Skyward::ORM::Migrations::Definitions.indexes(klass)
    pairs = table.indexes.map do |index|
      [index, index.with(columns: moved(index.columns, renamed))]
    end #: Array[[Skyward::ORM::Catalog::Index, Skyward::ORM::Catalog::Index]]
    moved = pairs.map(&:last)
    dropped = pairs.reject { |_, index| wanted.any? { |want| same_index?(index, want) } }
    [
      dropped.map { |index, _| Skyward::ORM::Migrations::DropIndex.new(index:) },
      wanted.reject { |want| moved.any? { |index| same_index?(index, want) } }
            .map { |index| Skyward::ORM::Migrations::AddIndex.new(index:) }
    ]
  end

  # The constraints to drop and to add, compared as indexes are. A new
  # column's own constraints are part of its definition.
  # @rbs (singleton(Skyward::ORM::Record) klass, Array[Skyward::ORM::Tables::Column] columns,
  #   Skyward::ORM::Catalog::Table table, Hash[Symbol, Symbol] renamed, Array[Skyward::ORM::Tables::Column] new_columns)
  #   -> [Array[Skyward::ORM::Migrations::edit], Array[Skyward::ORM::Migrations::edit]]
  def constraints(klass, columns, table, renamed, new_columns)
    wanted = Skyward::ORM::Migrations::Definitions.constraints(klass, columns)
    pairs = table.constraints.map do |constraint|
      [constraint, constraint.with(columns: moved(constraint.columns, renamed))]
    end #: Array[[Skyward::ORM::Catalog::Constraint, Skyward::ORM::Catalog::Constraint]]
    moved = pairs.map(&:last)
    dropped = pairs.reject { |_, constraint| wanted.any? { |want| same?(constraint, want) } }
    added = wanted.reject do |want|
      moved.any? { |constraint| same?(constraint, want) } || inline?(want, new_columns)
    end
    [
      dropped.map { |constraint, _| Skyward::ORM::Migrations::DropConstraint.new(constraint:) },
      added.map { |constraint| Skyward::ORM::Migrations::AddConstraint.new(constraint:) }
    ]
  end

  # Each column that went is asked about each new one of a compatible type, in
  # order, until one is a rename. A column it renames to isn't asked about again.
  # @rbs (Symbol table, Array[Skyward::ORM::Catalog::Column] removed, Array[Skyward::ORM::Tables::Column] added,
  #   Skyward::ORM::_Adapter adapter, ^(Symbol table, Symbol from, Symbol to) -> bool rename) -> Hash[Symbol, Symbol]
  def renames(table, removed, added, adapter, rename)
    none = {} #: Hash[Symbol, Symbol]
    removed.reduce(none) do |renamed, gone|
      to = added.find do |column|
        !renamed.value?(column.name) && adapter.compatible?(column.type, gone.type) &&
          rename.call(table, gone.name, column.name)
      end
      to ? renamed.merge(gone.name => to.name) : renamed
    end
  end

  # An untyped column has no type or nullability to compare.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs had: Skyward::ORM::Catalog::Column
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: Array[Skyward::ORM::Migrations::edit]
  def changed(klass, column, had, adapter)
    name = column.name
    sql_type = adapter.sql_type(column.type)
    retyped = sql_type unless adapter.compatible?(column.type, had.type)
    default = Skyward::ORM::Migrations::Definitions.default(klass, name, adapter)
    redefaulted = had.default != default
    renulled = sql_type && had.nullable != column.nullable
    [
      (Skyward::ORM::Migrations::ChangeType.new(column: name, from: had.type, to: retyped) if retyped),
      (Skyward::ORM::Migrations::ChangeDefault.new(column: name, from: had.default, to: default) if redefaulted),
      (Skyward::ORM::Migrations::ChangeNullable.new(column: name, nullable: column.nullable) if renulled)
    ].compact
  end

  # Constraints are matched by name. SQLite can hold one with no name, which
  # matches the one its class declares on the same columns. PostgreSQL rewrites
  # a check's expression, and puts it on every column it mentions, so a check
  # is matched by its name alone. A reference is also matched by what it does
  # ON DELETE.
  # @rbs had: Skyward::ORM::Catalog::Constraint
  # @rbs wanted: Skyward::ORM::Catalog::Constraint
  # @rbs return: bool
  def same?(had, wanted)
    name = had.name
    same_columns = had.columns == wanted.columns && had.references == wanted.references &&
                   on_delete(had) == on_delete(wanted)
    had.kind == wanted.kind && (name ? name == wanted.name && (had.kind == :check || same_columns) : same_columns)
  end

  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def on_delete(constraint)
    action = constraint.definition[ON_DELETE, 1]
    action ? action.upcase.gsub(/\s+/, " ") : "NO ACTION"
  end

  # An index is matched by its columns, so one a database already has under
  # another name is kept.
  # @rbs had: Skyward::ORM::Catalog::Index
  # @rbs wanted: Skyward::ORM::Catalog::Index
  # @rbs return: bool
  def same_index?(had, wanted) = !had.unique && had.columns == wanted.columns

  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs added: Array[Skyward::ORM::Tables::Column]
  # @rbs return: bool
  def inline?(constraint, added)
    constraint.columns.one? && added.any? { |column| column.name == constraint.columns.fetch(0) }
  end

  # @rbs columns: Array[Symbol]
  # @rbs renamed: Hash[Symbol, Symbol]
  # @rbs return: Array[Symbol]
  def moved(columns, renamed) = columns.map { |column| renamed.fetch(column, column) }

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
