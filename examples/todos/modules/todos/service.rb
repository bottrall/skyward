# frozen_string_literal: true

# rbs_inline: enabled

module Todos::Service
  extend self

  # @rbs done: bool?
  # @rbs limit: Integer
  # @rbs return: Array[Todos::Record]
  def list(done:, limit:)
    newest = Todos::Record.order(id: :desc).limit(limit)
    (done.nil? ? newest : newest.where(done:)).to_a
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record?
  def find(id) = Todos::Record.find_by(id:)

  # @rbs title: String
  # @rbs priority: Todos::Record::priority
  # @rbs due_on: Date?
  # @rbs list_id: Integer?
  # @rbs return: Todos::Record | :no_such_list | :invalid_title
  def create(title:, priority:, due_on:, list_id:)
    todo = Todos::Record.insert(title:, priority:, due_on:, list_id:)
    case todo
    when Todos::Record then todo
    # The API checks the priority's values, so the title's length and the list
    # are what the database can refuse.
    else todo.kind == :foreign_key ? :no_such_list : :invalid_title
    end
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record?
  def complete(id) = Todos::Record.where(id:).update!(done: true).first

  # @rbs id: Integer
  # @rbs return: Todos::Record?
  def delete(id) = Todos::Record.where(id:).delete!.first
end
