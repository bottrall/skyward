# frozen_string_literal: true

# Steep checks each method against its signature, so each write's result type,
# and the query merge returns, is pinned here with no annotation at its call.
module WritesFixtures
  class Todo < Skyward::ORM::Record
    table :todos

    # @dynamic id, title, done
    attr_reader :id, :title, :done
  end

  Id = Data.define(:id)

  module Writes
    def insert = Todo.insert(title: 'Buy milk')

    def insert! = Todo.insert!(title: 'Buy milk')

    def insert_into_table = Todo.into(Todo).insert(title: 'Buy milk')

    def insert_into_row = Todo.into(Id).insert(title: 'Buy milk')

    def insert_into_row! = Todo.into(Id).insert!(title: 'Buy milk')

    def insert_all = Todo.insert_all([{ title: 'Eggs' }, { title: 'Milk' }])

    def insert_all! = Todo.insert_all!([{ title: 'Eggs' }, { title: 'Milk' }])

    def insert_all_into_table = Todo.into(Todo).insert_all([{ title: 'Eggs' }, { title: 'Milk' }])

    def insert_all_into_row = Todo.into(Id).insert_all([{ title: 'Eggs' }, { title: 'Milk' }])

    def insert_all_into_row! = Todo.into(Id).insert_all!([{ title: 'Eggs' }, { title: 'Milk' }])

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

  module Merges
    def merge = Todo.where(done: false).merge(Todo.order(:id))

    def merge_into_row = Todo.into(Id).merge(Todo.where(done: false))
  end
end
