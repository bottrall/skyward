# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Adapters::SQLite::Constraints do
  def read(sql, columns) = Skyward::ORM::Adapters::SQLite::Constraints.read(sql, columns)

  def constraint(name, kind, columns, references = nil)
    Skyward::ORM::Catalog::Constraint.new(name:, kind:, columns:, references:)
  end

  describe ".read" do
    it "reads a column's own constraints, on that column" do
      sql = <<~SQL
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          list_id INTEGER NOT NULL REFERENCES lists (id) ON DELETE CASCADE,
          code TEXT UNIQUE,
          title TEXT NOT NULL DEFAULT 'untitled' CHECK (length(title) > 0)
        )
      SQL

      assert_equal [
        constraint(nil, :primary_key, [:id]),
        constraint(nil, :foreign_key, [:list_id], :lists),
        constraint(nil, :unique, [:code]),
        constraint(nil, :check, [:title])
      ],
                   read(sql, %i[id list_id code title])
    end

    it "names a constraint from its CONSTRAINT clause" do
      sql = "CREATE TABLE todos (id INTEGER CONSTRAINT todos_pkey PRIMARY KEY, code TEXT CONSTRAINT todos_key UNIQUE)"

      assert_equal [constraint("todos_pkey", :primary_key, [:id]), constraint("todos_key", :unique, [:code])],
                   read(sql, %i[id code])
    end

    it "reads a table constraint's columns from its parentheses" do
      sql = <<~SQL
        CREATE TABLE todos (
          list_id INTEGER, position INTEGER, title TEXT,
          PRIMARY KEY (list_id, position),
          CONSTRAINT todos_list_id_title_key UNIQUE (list_id, title COLLATE NOCASE),
          CONSTRAINT todos_list_id_fkey FOREIGN KEY (list_id) REFERENCES lists (id) ON DELETE CASCADE
        )
      SQL

      assert_equal [
        constraint(nil, :primary_key, %i[list_id position]),
        constraint("todos_list_id_title_key", :unique, %i[list_id title]),
        constraint("todos_list_id_fkey", :foreign_key, [:list_id], :lists)
      ],
                   read(sql, %i[list_id position title])
    end

    it "reads a table check as on the columns its expression mentions" do
      sql = "CREATE TABLE todos (title TEXT, notes TEXT, CHECK (length(TITLE) > 0 AND notes <> 'title'))"

      assert_equal [constraint(nil, :check, %i[title notes])], read(sql, %i[title notes])
    end

    it "reads quoted names, unescaping them" do
      sql = <<~SQL
        CREATE TABLE "to""dos" (
          "or""der" INTEGER CONSTRAINT "a ""b"" key" UNIQUE,
          `gro``up` TEXT CONSTRAINT `c d` UNIQUE,
          [user] TEXT CONSTRAINT [e f] UNIQUE
        )
      SQL

      assert_equal [
        constraint("a \"b\" key", :unique, [:"or\"der"]),
        constraint("c d", :unique, [:"gro`up"]),
        constraint("e f", :unique, [:user])
      ],
                   read(sql, %i[or"der gro`up user])
    end

    it "skips comments, and the commas and parentheses in strings and types" do
      sql = <<~SQL
        CREATE TABLE todos ( -- the todos, (with, commas)
          /* a (comment), here */
          price DECIMAL(10, 2) DEFAULT '(1, 2)' CHECK (price > 0)
        ) STRICT
      SQL

      assert_equal [constraint(nil, :check, [:price])], read(sql, [:price])
    end

    it "reads no constraints from a table that has none" do
      assert_empty read("CREATE TABLE todos (id INTEGER, title TEXT NOT NULL COLLATE NOCASE)", %i[id title])
    end
  end
end
