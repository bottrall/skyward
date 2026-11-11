# frozen_string_literal: true

module Skyward::ORM::Migrations::Script
  extend self

  # The column types of a primary key the database numbers.
  NUMBERED = %i[integer int32 int16].freeze #: Array[Skyward::ORM::Tables::column_type]

  # @rbs changes: Array[Skyward::ORM::Migrations::change]
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def write(changes, adapter)
    up = changes.map { |change| up(change, adapter) }.join("\n")
    down = changes.reverse.map { |change| down(change, adapter) }.join
    "#{up}\n-- down\n#{down}"
  end

  private

  # @rbs change: Skyward::ORM::Migrations::change
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def up(change, adapter)
    case change
    when Skyward::ORM::Migrations::CreateTable
      klass = change.klass
      "#{create_table(klass, change.columns, adapter, klass.table_name, {}, [])}#{indexes(klass)}"
    else
      return rebuild(change, adapter) unless in_place?(change, adapter)

      change.edits.map { |edit| forward(change, edit, adapter) }.join
    end
  end

  # @rbs change: Skyward::ORM::Migrations::change
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def down(change, adapter)
    case change
    when Skyward::ORM::Migrations::CreateTable then "DROP TABLE #{change.klass.table_name};\n"
    else
      return unbuild(change) unless in_place?(change, adapter)

      change.edits.reverse.map { |edit| backward(change, edit) }.join
    end
  end

  # SQLite can't alter a column or a constraint, so only what ALTER TABLE does
  # on every database is done in place: adding, dropping and renaming a
  # column, and indexes. It can't add a key column, or one whose default is an
  # expression, either.
  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: bool
  def in_place?(change, adapter)
    schema = change.klass.schema
    adapter.alters_in_place? || change.edits.all? do |edit|
      case edit
      when Skyward::ORM::Migrations::AddColumn
        name = edit.column.name
        !(schema.primary_key == name || schema.uniques.include?([name]) ||
          schema.defaults[name].is_a?(Skyward::ORM::Tables::SQL))
      when Skyward::ORM::Migrations::DropColumn, Skyward::ORM::Migrations::RenameColumn,
           Skyward::ORM::Migrations::AddIndex, Skyward::ORM::Migrations::DropIndex then true
      else false
      end
    end
  end

  # PostgreSQL changes a column's type with USING, which casts each value it has.
  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs edit: Skyward::ORM::Migrations::edit
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def forward(change, edit, adapter)
    klass = change.klass
    table = klass.table_name
    case edit
    when Skyward::ORM::Migrations::AddColumn then add_column(klass, change.columns, edit.column, adapter)
    when Skyward::ORM::Migrations::DropColumn then "ALTER TABLE #{table} DROP COLUMN #{edit.column.name};\n"
    when Skyward::ORM::Migrations::RenameColumn then rename(table, edit.from, edit.to)
    when Skyward::ORM::Migrations::ChangeType then retype(table, edit.column, edit.to)
    when Skyward::ORM::Migrations::ChangeNullable then nullable(table, edit.column, edit.nullable)
    when Skyward::ORM::Migrations::ChangeDefault then default(table, edit.column, edit.to)
    when Skyward::ORM::Migrations::AddConstraint then add_constraint(table, edit.constraint)
    when Skyward::ORM::Migrations::DropConstraint then drop_constraint(table, edit.constraint)
    when Skyward::ORM::Migrations::AddIndex then "#{edit.index.definition};\n"
    else "DROP INDEX #{edit.index.name};\n"
    end
  end

  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs edit: Skyward::ORM::Migrations::edit
  # @rbs return: String
  def backward(change, edit)
    table = change.klass.table_name
    case edit
    when Skyward::ORM::Migrations::AddColumn then "ALTER TABLE #{table} DROP COLUMN #{edit.column.name};\n"
    when Skyward::ORM::Migrations::DropColumn
      "#{restored(table, edit.column)}ALTER TABLE #{table} ADD COLUMN #{column(edit.column)};\n"
    when Skyward::ORM::Migrations::RenameColumn then rename(table, edit.to, edit.from)
    when Skyward::ORM::Migrations::ChangeType then retype(table, edit.column, edit.from)
    when Skyward::ORM::Migrations::ChangeNullable then nullable(table, edit.column, !edit.nullable)
    when Skyward::ORM::Migrations::ChangeDefault then default(table, edit.column, edit.from)
    when Skyward::ORM::Migrations::AddConstraint then drop_constraint(table, edit.constraint)
    when Skyward::ORM::Migrations::DropConstraint then add_constraint(table, edit.constraint)
    when Skyward::ORM::Migrations::AddIndex then "DROP INDEX #{edit.index.name};\n"
    else "#{edit.index.definition};\n"
    end
  end

  # SQLite rebuilds the table as its class has it, with what it keeps that the
  # class can't declare: create the new one, copy the rows of each column it
  # keeps, drop the old one, rename the new one and recreate its indexes.
  # Dropping a table another one references would run that one's ON DELETE,
  # so `skyward migrate` turns SQLite's foreign keys off around each
  # migration, and checks them before it commits.
  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def rebuild(change, adapter)
    klass = change.klass
    table = klass.table_name
    moved = renames(change)
    kept = change.table.columns.to_h { |column| [moved.fetch(column.name, column.name), column] }
    copied = change.columns.select { |column| kept.key?(column.name) }
    todos = change.edits.filter_map do |edit|
      case edit
      when Skyward::ORM::Migrations::AddColumn then needs_default(klass, edit.column)
      when Skyward::ORM::Migrations::ChangeNullable then backfill(table, edit.column) unless edit.nullable
      end
    end
    [
      *todos,
      create_table(klass, change.columns, adapter, :"#{table}_new", kept, change.kept_constraints),
      copy(table, copied.map(&:name), copied.map { |column| kept.fetch(column.name).name }),
      indexes(klass),
      *change.kept_indexes.map { |index| "#{index.definition};\n" }
    ].join
  end

  # The table goes back as the database had it, from what was read of it.
  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs return: String
  def unbuild(change)
    had = change.table
    table = had.name
    moved = renames(change)
    current = change.columns.map(&:name)
    copied = had.columns.select { |column| current.include?(moved.fetch(column.name, column.name)) }
    restored = change.edits.filter_map do |edit|
      restored(table, edit.column) if edit.is_a?(Skyward::ORM::Migrations::DropColumn)
    end
    name_width = had.columns.map { |column| column.name.length }.max || 0
    type_width = had.columns.map { |column| column.type.length }.max || 0
    lines = [
      *had.columns.map do |column|
        "#{column.name.name.ljust(name_width)}  #{column.type.ljust(type_width)} #{clauses(column)}".rstrip
      end,
      *had.constraints.map { |constraint| table_constraint(constraint) }
    ]
    [
      *restored,
      "CREATE TABLE #{table}_new (\n#{lines.map { |line| "  #{line}" }.join(",\n")}\n);\n",
      copy(table, copied.map(&:name), copied.map { |column| moved.fetch(column.name, column.name) }),
      *had.indexes.map { |index| "#{index.definition};\n" }
    ].join
  end

  # @rbs change: Skyward::ORM::Migrations::AlterTable
  # @rbs return: Hash[Symbol, Symbol]
  def renames(change)
    pairs = change.edits.filter_map do |edit|
      case edit
      when Skyward::ORM::Migrations::RenameColumn then [edit.from, edit.to]
      end
    end #: Array[[Symbol, Symbol]]
    pairs.to_h
  end

  # @rbs table: Symbol
  # @rbs into: Array[Symbol]
  # @rbs from: Array[Symbol]
  # @rbs return: String
  def copy(table, into, from)
    "INSERT INTO #{table}_new (#{into.join(", ")}) SELECT #{from.join(", ")} FROM #{table};\n" \
      "DROP TABLE #{table};\n" \
      "ALTER TABLE #{table}_new RENAME TO #{table};\n"
  end

  # Columns line up as a person would write them. A generated key's type runs
  # on into its identity clause, so it doesn't set the width. A rebuild keeps
  # the type an untyped column has, and the constraints the class can't declare.
  # @rbs (singleton(Skyward::ORM::Record) klass, Array[Skyward::ORM::Tables::Column] columns,
  #   Skyward::ORM::_Adapter adapter, Symbol name, Hash[Symbol, Skyward::ORM::Catalog::Column] kept,
  #   Array[Skyward::ORM::Catalog::Constraint] undeclared) -> String
  def create_table(klass, columns, adapter, name, kept, undeclared)
    schema = klass.schema
    constraints = Skyward::ORM::Migrations::Definitions.constraints(klass, columns)
    name_width = columns.map { |column| column.name.length }.max || 0
    identity = adapter.identity
    type_width = columns.reject { |column| identity && generated?(schema, column) }
                        .filter_map { |column| (adapter.sql_type(column.type) || kept[column.name]&.type)&.length }
                        .max || 0
    lines = columns.map do |column|
      found = definition(klass, column, adapter, constraints, kept[column.name])
      next [false, todo_type(klass.table_name, column)] unless found

      spec, clauses = found
      [true, "#{column.name.name.ljust(name_width)}  #{spec.ljust(type_width)} #{clauses}".rstrip]
    end #: Array[[bool, String]]
    multi_column = constraints.reject { |constraint| constraint.columns.one? }
    table_constraints = [*multi_column, *undeclared].map do |constraint|
      [true, table_constraint(constraint)]
    end #: Array[[bool, String]]
    entries = [*lines, *table_constraints]
    last = entries.rindex { |definition, _| definition }
    body = entries.each_with_index.map do |(definition, text), index|
      "  #{text}#{"," if definition && index != last}\n"
    end
    ["CREATE TABLE #{name} (\n", *body, ");\n"].join
  end

  # SQLite can hold a constraint with no name.
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def table_constraint(constraint) = "#{"CONSTRAINT #{constraint.name} " if constraint.name}#{constraint.definition}"

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs return: String
  def indexes(klass)
    Skyward::ORM::Migrations::Definitions.indexes(klass).map { |index| "#{index.definition};\n" }.join
  end

  # @rbs (singleton(Skyward::ORM::Record) klass, Array[Skyward::ORM::Tables::Column] columns,
  #   Skyward::ORM::Tables::Column column, Skyward::ORM::_Adapter adapter) -> String
  def add_column(klass, columns, column, adapter)
    table = klass.table_name
    constraints = Skyward::ORM::Migrations::Definitions.constraints(klass, columns)
    found = definition(klass, column, adapter, constraints, nil)
    return "#{todo_type(table, column)}\n" unless found

    spec, clauses = found
    "#{needs_default(klass, column)}ALTER TABLE #{table} ADD COLUMN #{"#{column.name} #{spec} #{clauses}".rstrip};\n"
  end

  # A column's type, and the clauses that follow it, or nil when it has no
  # type. One with no type keeps the one the table has, if it has one.
  # @rbs (singleton(Skyward::ORM::Record) klass, Skyward::ORM::Tables::Column column, Skyward::ORM::_Adapter adapter,
  #   Array[Skyward::ORM::Catalog::Constraint] constraints, Skyward::ORM::Catalog::Column? kept) -> [String, String]?
  def definition(klass, column, adapter, constraints, kept)
    typed = adapter.sql_type(column.type)
    sql_type = typed || kept&.type
    return unless sql_type

    name = column.name
    generated = generated?(klass.schema, column)
    default = Skyward::ORM::Migrations::Definitions.default(klass, column, adapter)
    clauses = [
      ("NOT NULL" unless (typed ? column.nullable : kept&.nullable) || generated),
      ("DEFAULT #{default}" if default),
      *constraints.select { |constraint| constraint.columns == [name] }
                  .map { |constraint| Skyward::ORM::Migrations::Definitions.inline(constraint) }
    ].compact
    [[sql_type, (adapter.identity if generated)].compact.join(" "), clauses.join(" ")]
  end

  # @rbs schema: Skyward::ORM::Tables::Schema
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: bool
  def generated?(schema, column) = schema.primary_key == column.name && NUMBERED.include?(column.type)

  # A column as the database has it.
  # @rbs column: Skyward::ORM::Catalog::Column
  # @rbs return: String
  def column(column) = [column.name, (column.type unless column.type.empty?), clauses(column)].compact.join(" ").rstrip

  # @rbs column: Skyward::ORM::Catalog::Column
  # @rbs return: String
  def clauses(column)
    [("NOT NULL" unless column.nullable), ("DEFAULT #{column.default}" if column.default)].compact.join(" ")
  end

  # @rbs table: Symbol
  # @rbs from: Symbol
  # @rbs to: Symbol
  # @rbs return: String
  def rename(table, from, to) = "ALTER TABLE #{table} RENAME COLUMN #{from} TO #{to};\n"

  # @rbs table: Symbol
  # @rbs column: Symbol
  # @rbs type: String
  # @rbs return: String
  def retype(table, column, type)
    "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE #{type} USING #{column}::#{type};\n"
  end

  # @rbs table: Symbol
  # @rbs column: Symbol
  # @rbs nullable: bool
  # @rbs return: String
  def nullable(table, column, nullable)
    return "ALTER TABLE #{table} ALTER COLUMN #{column} DROP NOT NULL;\n" if nullable

    "#{backfill(table, column)}ALTER TABLE #{table} ALTER COLUMN #{column} SET NOT NULL;\n"
  end

  # @rbs table: Symbol
  # @rbs column: Symbol
  # @rbs value: String?
  # @rbs return: String
  def default(table, column, value)
    "ALTER TABLE #{table} ALTER COLUMN #{column} #{value ? "SET DEFAULT #{value}" : "DROP DEFAULT"};\n"
  end

  # @rbs table: Symbol
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def add_constraint(table, constraint)
    "ALTER TABLE #{table} ADD #{"CONSTRAINT #{constraint.name} " if constraint.name}#{constraint.definition};\n"
  end

  # @rbs table: Symbol
  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def drop_constraint(table, constraint) = "ALTER TABLE #{table} DROP CONSTRAINT #{constraint.name};\n"

  # The rows a table already has need a value for a new required column.
  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: String?
  def needs_default(klass, column)
    return if column.nullable || klass.schema.defaults.key?(column.name)

    todo_default(klass.table_name, column.name)
  end

  # @rbs table: Symbol
  # @rbs column: Skyward::ORM::Catalog::Column
  # @rbs return: String
  def restored(table, column)
    "-- #{table}.#{column.name} comes back empty: dropping it lost its data\n" \
      "#{todo_default(table, column.name) unless column.nullable || column.default}"
  end

  # @rbs table: Symbol
  # @rbs column: Symbol
  # @rbs return: String
  def todo_default(table, column) = "-- TODO: #{table}.#{column} needs a DEFAULT for the rows #{table} already has\n"

  # @rbs table: Symbol
  # @rbs column: Symbol
  # @rbs return: String
  def backfill(table, column) = "-- TODO: backfill the NULLs in #{table}.#{column} before it becomes NOT NULL\n"

  # @rbs table: Symbol
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs return: String
  def todo_type(table, column) = "-- TODO: #{table}.#{column.name} needs a type"
end
