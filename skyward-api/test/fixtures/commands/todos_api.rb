# frozen_string_literal: true

# The README's TodosAPI, with the method signatures rbs-inline writes for it in sig/todos_api.rbs.
Todo = Data.define(:id, :title, :priority, :due_on, :done)

NewTodo = Data.define(:title, :priority, :due_on)

class TodosAPI < Skyward::API
  description "Things to do, and the satisfaction of ticking them off."

  get    "/",             to: :index,    summary: "List todos, newest first."
  get    "/:id",          to: :show,     summary: "Fetch a single todo."
  post   "/",             to: :create,   summary: "Create a todo."
  post   "/:id/complete", to: :complete, summary: "Mark a todo as done."
  delete "/:id",          to: :destroy,  summary: "Delete a todo."

  def initialize(todos:)
    super()
    @todos = todos
  end

  def index(done: nil, limit: 50) = @todos.list(done:, limit:)

  def show(id:) = @todos.find(id) || not_found

  def create(body:) = created @todos.create(**body.to_h)

  def complete(id:) = @todos.complete(id) || not_found

  def destroy(id:) = @todos.delete(id) ? no_content : not_found
end
