# frozen_string_literal: true

module Skyward::ORM::Migrations::Summary
  extend self

  # @rbs changes: Array[Skyward::ORM::Migrations::change]
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def text(changes, adapter) = changes.map { |change| section(change, adapter) }.join

  private

  # Each change is a line, marked + for what's added, - for what's dropped,
  # and ~ for what's changed, and the lines line up after what each names.
  # @rbs change: Skyward::ORM::Migrations::change
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def section(change, adapter)
    klass = change.klass
    table = klass.table_name
    case change
    when Skyward::ORM::Migrations::CreateTable
      "#{klass} has no table yet:\n  + #{table}  #{counts(change)}\n"
    else
      lines = change.edits.map { |edit| line(edit, adapter) }
      width = lines.map { |_, name, _| name.length }.max || 0
      ["#{klass} differs from the #{table} table:\n", *lines.map do |mark, name, text|
        "  #{mark} #{name.ljust(width)}  #{text}\n"
      end].join
    end
  end

  # @rbs edit: Skyward::ORM::Migrations::edit
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: [String, String, String]
  def line(edit, adapter)
    case edit
    when Skyward::ORM::Migrations::AddColumn then ["+", edit.column.name.name, column(edit.column, adapter)]
    when Skyward::ORM::Migrations::DropColumn
      ["-", edit.column.name.name, "#{edit.column.type} #{edit.column.nullable ? "NULL" : "NOT NULL"}".lstrip]
    when Skyward::ORM::Migrations::RenameColumn then ["~", edit.to.name, "renamed from #{edit.from}"]
    when Skyward::ORM::Migrations::ChangeType then ["~", edit.column.name, "#{edit.to}, was #{edit.from}"]
    when Skyward::ORM::Migrations::ChangeNullable
      ["~", edit.column.name, edit.nullable ? "NULL, was NOT NULL" : "NOT NULL, was NULL"]
    when Skyward::ORM::Migrations::ChangeDefault then ["~", edit.column.name,
                                                       "#{default(edit.to)}, was #{default(edit.from)}"]
    when Skyward::ORM::Migrations::AddConstraint then ["+", edit.constraint.name.to_s, constraint(edit.constraint)]
    when Skyward::ORM::Migrations::DropConstraint then ["-", edit.constraint.name || "unnamed",
                                                        constraint(edit.constraint)]
    when Skyward::ORM::Migrations::RenameConstraint then ["~", edit.to, "renamed from #{edit.from}"]
    when Skyward::ORM::Migrations::AddIndex then ["+", edit.index.name, index(edit.index)]
    else ["-", edit.index.name, index(edit.index)]
    end
  end

  # @rbs change: Skyward::ORM::Migrations::CreateTable
  # @rbs return: String
  def counts(change)
    schema = change.klass.schema
    declared = [
      [schema.references.size, "reference", "references"],
      [schema.checks.size + change.columns.count { |column| column.type == :enum }, "check", "checks"],
      [schema.uniques.size, "unique", "uniques"],
      [schema.indexes.size, "index", "indexes"]
    ] #: Array[[Integer, String, String]]
    [
      count(change.columns.size, "column", "columns"),
      *declared.filter_map { |size, one, many| count(size, one, many) if size.positive? }
    ].join(", ")
  end

  # @rbs size: Integer
  # @rbs one: String
  # @rbs many: String
  # @rbs return: String
  def count(size, one, many) = "#{size} #{size == 1 ? one : many}"

  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def column(column, adapter)
    sql_type = adapter.sql_type(column)
    return "needs a type" unless sql_type

    "#{sql_type} #{column.nullable ? "NULL" : "NOT NULL"}"
  end

  # @rbs default: String?
  # @rbs return: String
  def default(default) = default ? "DEFAULT #{default}" : "no default"

  # @rbs constraint: Skyward::ORM::Catalog::Constraint
  # @rbs return: String
  def constraint(constraint)
    columns = "(#{constraint.columns.join(", ")})"
    case constraint.kind
    when :primary_key then "primary key #{columns}"
    when :unique then "unique #{columns}"
    when :check then "check #{columns}"
    else "reference #{columns} to #{constraint.references}"
    end
  end

  # @rbs index: Skyward::ORM::Catalog::Index
  # @rbs return: String
  def index(index) = "index (#{index.columns.join(", ")})"
end
