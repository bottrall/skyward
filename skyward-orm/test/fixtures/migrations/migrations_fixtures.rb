# frozen_string_literal: true

require "date"

module MigrationsFixtures
  class List < Skyward::ORM::Record
    table :lists

    attr_reader :id, :name
  end

  # The README's Todo, with a default SQLite can run.
  class Todo < Skyward::ORM::Record
    table :todos
    references :list_id, List, on_delete: :cascade
    default priority: :normal, done: false, created_at: Skyward.sql("CURRENT_TIMESTAMP")
    check :title, length: 1..200
    index :list_id, :done

    attr_reader :id, :list_id, :title, :priority, :due_on, :done, :created_at
  end

  # The README's Todo once it has notes, and a required column that needs a default.
  class NotedTodo < Skyward::ORM::Record
    table :todos
    default rank: 0

    attr_reader :id, :list_id, :title, :priority, :due_on, :done, :created_at, :notes, :rank, :code, :extra
  end

  # Sorts before the todos it references.
  class Attachment < Skyward::ORM::Record
    table :attachments
    references :todo_id, Todo

    attr_reader :id, :todo_id
  end

  # Every declaration Todo doesn't make.
  class Member < Skyward::ORM::Record
    table :members
    primary_key :email
    references :list_id, List, on_delete: :set_null
    references :mentor_email, Member
    default nickname: "it's me", score: 1.5, joined_on: Date.new(2026, 10, 18), note: nil
    unique :handle
    unique :list_id, :handle
    check :handle, length: (3..)
    check :handle, Skyward.sql("handle = lower(handle)")
    check :nickname, length: ..20

    attr_reader :email, :list_id, :mentor_email, :handle, :nickname, :score, :joined_on, :role, :note
  end

  # Its last column has no type.
  class Scrap < Skyward::ORM::Record
    table :scraps

    attr_reader :id, :payload
  end

  # The README's rework_todos: notes renamed to details, due_on required, and
  # an index on it.
  def self.rework_todos
    [
      Skyward::ORM::Migrations::RenameColumn.new(from: :notes, to: :details),
      Skyward::ORM::Migrations::ChangeNullable.new(column: :due_on, nullable: false),
      Skyward::ORM::Migrations::AddIndex.new(
        index: Skyward::ORM::Catalog::Index.new(
          name: "todos_due_on_index",
          columns: [:due_on],
          unique: false,
          definition: "CREATE INDEX todos_due_on_index ON todos (due_on)"
        )
      )
    ]
  end
end
