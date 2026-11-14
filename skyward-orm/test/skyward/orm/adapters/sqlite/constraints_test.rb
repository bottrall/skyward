# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::Adapters::SQLite::Constraints do
  def read(sql, columns) = Skyward::ORM::Adapters::SQLite::Constraints.read(sql, columns)

  def constraint(name, kind, columns, definition, references = nil)
    Skyward::ORM::Catalog::Constraint.new(name:, kind:, columns:, references:, definition:)
  end

  describe '.read' do
    it "reads a column's own constraints, on that column, as the table constraints they're the same as" do
      sql = <<~SQL
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          list_id INTEGER NOT NULL REFERENCES lists (id) ON DELETE CASCADE,
          code TEXT UNIQUE,
          title TEXT NOT NULL DEFAULT 'untitled' CHECK (length(title) > 0)
        )
      SQL

      assert_equal [
        constraint(nil, :primary_key, [:id], 'PRIMARY KEY (id)'),
        constraint(
          nil,
          :foreign_key,
          [:list_id],
          'FOREIGN KEY (list_id) REFERENCES lists (id) ON DELETE CASCADE',
          :lists
        ),
        constraint(nil, :unique, [:code], 'UNIQUE (code)'),
        constraint(nil, :check, [:title], 'CHECK (length(title) > 0)')
      ],
                   read(sql, %i[id list_id code title])
    end

    it 'names a constraint from its CONSTRAINT clause' do
      sql = 'CREATE TABLE todos (id INTEGER CONSTRAINT todos_pkey PRIMARY KEY, code TEXT CONSTRAINT todos_key UNIQUE)'

      assert_equal [
        constraint('todos_pkey', :primary_key, [:id], 'PRIMARY KEY (id)'),
        constraint('todos_key', :unique, [:code], 'UNIQUE (code)')
      ],
                   read(sql, %i[id code])
    end

    it "ends a column's constraint at its next clause, but not at SET NULL, SET DEFAULT or NOT DEFERRABLE" do
      sql = <<~SQL
        CREATE TABLE todos (
          a INTEGER REFERENCES lists ON DELETE SET NULL NOT DEFERRABLE CHECK (a > 0) NOT NULL,
          b INTEGER CONSTRAINT todos_b_check CHECK (b > 0) CONSTRAINT todos_b_fkey REFERENCES lists ON UPDATE SET DEFAULT DEFAULT 1
        )
      SQL

      assert_equal [
        constraint(
          nil,
          :foreign_key,
          [:a],
          'FOREIGN KEY (a) REFERENCES lists ON DELETE SET NULL NOT DEFERRABLE',
          :lists
        ),
        constraint(nil, :check, [:a], 'CHECK (a > 0)'),
        constraint('todos_b_check', :check, [:b], 'CHECK (b > 0)'),
        constraint('todos_b_fkey', :foreign_key, [:b], 'FOREIGN KEY (b) REFERENCES lists ON UPDATE SET DEFAULT', :lists)
      ],
                   read(sql, %i[a b])
    end

    it "reads a table constraint's columns from its parentheses, and its definition as written" do
      sql = <<~SQL
        CREATE TABLE todos (
          list_id INTEGER, position INTEGER, title TEXT,
          PRIMARY KEY (list_id, position),
          CONSTRAINT todos_list_id_title_key UNIQUE (list_id, title COLLATE NOCASE),
          CONSTRAINT todos_list_id_fkey FOREIGN KEY (list_id) REFERENCES lists (id) ON DELETE CASCADE
        )
      SQL

      assert_equal [
        constraint(nil, :primary_key, %i[list_id position], 'PRIMARY KEY (list_id, position)'),
        constraint('todos_list_id_title_key', :unique, %i[list_id title], 'UNIQUE (list_id, title COLLATE NOCASE)'),
        constraint(
          'todos_list_id_fkey',
          :foreign_key,
          [:list_id],
          'FOREIGN KEY (list_id) REFERENCES lists (id) ON DELETE CASCADE',
          :lists
        )
      ],
                   read(sql, %i[list_id position title])
    end

    it 'reads a table check as on the columns its expression mentions' do
      sql = "CREATE TABLE todos (title TEXT, notes TEXT, CHECK (length(TITLE) > 0 AND notes <> 'title'))"

      assert_equal [constraint(nil, :check, %i[title notes], "CHECK (length(TITLE) > 0 AND notes <> 'title')")],
                   read(sql, %i[title notes])
    end

    it "reads quoted names, unescaping them, and keeps a definition's quotes" do
      sql = <<~SQL
        CREATE TABLE "to""dos" (
          "or""der" INTEGER CONSTRAINT "a ""b"" key" UNIQUE,
          `gro``up` TEXT CONSTRAINT `c d` UNIQUE,
          [user] TEXT CONSTRAINT [e f] REFERENCES "us""ers"
        )
      SQL

      assert_equal [
        constraint('a "b" key', :unique, [:'or"der'], 'UNIQUE (or"der)'),
        constraint('c d', :unique, [:'gro`up'], 'UNIQUE (gro`up)'),
        constraint('e f', :foreign_key, [:user], 'FOREIGN KEY (user) REFERENCES "us""ers"', :'us"ers')
      ],
                   read(sql, %i[or"der gro`up user])
    end

    it 'skips comments, and the commas and parentheses in strings and types' do
      sql = <<~SQL
        CREATE TABLE todos ( -- the todos, (with, commas)
          /* a (comment), here */
          price DECIMAL(10, 2) DEFAULT '(1, 2)' CHECK (price > 0)
        ) STRICT
      SQL

      assert_equal [constraint(nil, :check, [:price], 'CHECK (price > 0)')], read(sql, [:price])
    end

    it 'reads no constraints from a table that has none' do
      assert_empty read('CREATE TABLE todos (id INTEGER, title TEXT NOT NULL COLLATE NOCASE)', %i[id title])
    end
  end

  describe '.generated' do
    def generated(sql) = Skyward::ORM::Adapters::SQLite::Constraints.generated(sql)

    it "reads each generated column's expression as written, stored or virtual, but not an AS inside an expression" do
      sql = <<~SQL
        CREATE TABLE todos (
          title TEXT NOT NULL CHECK (CAST(title AS TEXT) <> ''),
          "search" TEXT NOT NULL GENERATED ALWAYS AS (lower(title) || ' (' || id || ')') STORED,
          length INTEGER AS (length(title)) VIRTUAL
        )
      SQL

      assert_equal({ search: "lower(title) || ' (' || id || ')'", length: 'length(title)' }, generated(sql))
    end

    it 'reads none from a table that has none' do
      assert_empty generated('CREATE TABLE todos (id INTEGER, title TEXT NOT NULL COLLATE NOCASE)')
    end
  end
end
