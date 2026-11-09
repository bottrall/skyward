# frozen_string_literal: true

module Skyward::ORM::Migrations::Summary
  extend self

  # @rbs changes: Array[Skyward::ORM::Migrations::change]
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs return: String
  def text(changes, adapter) = changes.map { |change| section(change, adapter) }.join

  private

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
      width = change.columns.map { |column| column.name.length }.max || 0
      lines = change.columns.map { |column| "  + #{column.name.name.ljust(width)}  #{column(column, adapter)}\n" }
      ["#{klass} differs from the #{table} table:\n", *lines].join
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
    sql_type = adapter.sql_type(column.type)
    return "needs a type" unless sql_type

    "#{sql_type} #{column.nullable ? "NULL" : "NOT NULL"}"
  end
end
