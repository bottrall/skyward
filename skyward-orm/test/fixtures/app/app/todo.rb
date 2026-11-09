# frozen_string_literal: true

class Todo < Skyward::ORM::Record
  table :todos
  references :list_id, List, on_delete: :cascade
  default priority: :normal, done: false, created_at: Skyward.sql("CURRENT_TIMESTAMP")
  check :title, length: 1..200
  index :list_id, :done

  attr_reader :id, :list_id, :title, :priority, :due_on, :done, :created_at
end
