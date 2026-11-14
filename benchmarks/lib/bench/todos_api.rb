# frozen_string_literal: true

# rbs_inline: enabled

# @rbs use Skyward::API::*

class Bench::TodosAPI < Skyward::API
  get  '/:id', to: :show
  post '/',    to: :create

  Todo = Data.define(
    :id,      #: Integer
    :title,   #: String
    :done,    #: bool
    :due_on,  #: Date?
    :tags     #: Array[String]
  )

  NewTodo = Data.define(
    :title,   #: String
    :done,    #: bool
    :due_on,  #: Date?
    :tags     #: Array[String]
  )

  # @rbs @todos: Hash[Integer, Todo]

  # @rbs todos: Hash[Integer, Todo]
  # @rbs return: void
  def initialize(todos:)
    super()
    @todos = todos
  end

  # @rbs id: Integer
  # @rbs return: Todo | Responses::NotFound
  def show(id:)
    @todos[id] || not_found
  end

  # Nothing is kept, so timing millions of posts doesn't grow the store.
  # @rbs body: NewTodo
  # @rbs return: Responses::Created[Todo]
  def create(body:)
    created Todo.new(id: @todos.size + 1, title: body.title, done: body.done, due_on: body.due_on, tags: body.tags)
  end
end
