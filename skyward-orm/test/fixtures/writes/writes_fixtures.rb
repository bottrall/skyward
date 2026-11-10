# frozen_string_literal: true

# Steep checks each method against its signature, so each write's result type
# is pinned here with no annotation at its call.
module WritesFixtures
  class Todo < Skyward::ORM::Record
    table :todos

    # @dynamic id, title, done
    attr_reader :id, :title, :done
  end

  Id = Data.define(:id)

  module Writes
    def insert = Todo.insert(title: "Buy milk")

    def insert! = Todo.insert!(title: "Buy milk")

    def insert_into_table = Todo.into(Todo).insert(title: "Buy milk")

    def insert_into_row = Todo.into(Id).insert(title: "Buy milk")

    def insert_into_row! = Todo.into(Id).insert!(title: "Buy milk")

    def update(id) = Todo.where(id:).update(done: true)

    def update!(id) = Todo.where(id:).update!(done: true)

    def update_into_row(id) = Todo.where(id:).into(Id).update(done: true)

    def update_into_table!(id) = Todo.where(id:).into(Todo).update!(done: true)

    def update_into_row_narrowed(id) = Todo.into(Id).where(id:).update(done: true)

    def delete = Todo.where(done: true).delete

    def delete! = Todo.where(done: true).delete!

    def delete_into_row = Todo.where(done: true).into(Id).delete

    def delete_into_table! = Todo.where(done: true).into(Todo).delete!
  end
end
