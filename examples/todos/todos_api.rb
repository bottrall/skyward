# frozen_string_literal: true

# @rbs use Skyward::*

require_relative "new_todo"
require_relative "todo"

class TodosAPI < Skyward::API
  description "Things to do, and the satisfaction of ticking them off."

  get    "/",             to: :index,    summary: "List todos, newest first."
  get    "/:id",          to: :show,     summary: "Fetch a single todo."
  post   "/",             to: :create,   summary: "Create a todo."
  post   "/:id/complete", to: :complete, summary: "Mark a todo as done.", description: <<~TEXT
    Marking a todo that's already done is fine: it stays done, and the
    response is the same.
  TEXT
  delete "/:id", to: :destroy, summary: "Delete a todo."

  # @rbs @todos: TodoStore

  # @rbs todos: TodoStore
  # @rbs return: void
  def initialize(todos:)
    super()
    @todos = todos
  end

  # @rbs done: bool?
  # @rbs limit: Integer
  # @rbs return: Array[Todo]
  def index(done: nil, limit: 50)
    @todos.list(done:, limit:)
  end

  # @rbs id: Integer
  # @rbs return: Todo | NotFound
  def show(id:)
    @todos.find(id) || not_found
  end

  # @rbs body: NewTodo
  # @rbs return: Created[Todo]
  def create(body:)
    created @todos.create(title: body.title, priority: body.priority, due_on: body.due_on)
  end

  # @rbs id: Integer
  # @rbs return: Todo | NotFound
  def complete(id:)
    @todos.complete(id) || not_found
  end

  # @rbs id: Integer
  # @rbs return: NoContent | NotFound
  def destroy(id:)
    @todos.delete(id) ? no_content : not_found
  end
end
