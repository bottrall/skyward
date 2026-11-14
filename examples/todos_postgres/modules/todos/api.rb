# frozen_string_literal: true

# rbs_inline: enabled

# @rbs use Skyward::API::*

class Todos::API < Skyward::API
  description 'Things to do, and the satisfaction of ticking them off.'

  get    '/',             to: :index,    summary: 'List todos, newest first.'
  get    '/:id',          to: :show,     summary: 'Fetch a single todo.'
  post   '/',             to: :create,   summary: 'Create a todo.'
  post   '/:id/complete', to: :complete, summary: 'Mark a todo as done.', description: <<~TEXT
    Marking a todo that's already done is fine: it stays done, and the
    response is the same.
  TEXT
  delete '/:id', to: :destroy, summary: 'Delete a todo.'

  NewTodo = Data.define(
    :title,     #: String
    :priority,  #: Todos::Record::priority
    :due_on,    #: Date?
    :list_id    #: Integer?
  )

  # @rbs @todos: singleton(Todos::Service)

  # @rbs todos: singleton(Todos::Service)
  # @rbs return: void
  def initialize(todos:)
    super()
    @todos = todos
  end

  # @rbs done: bool?
  # @rbs limit: Integer
  # @rbs return: Array[Todos::Record]
  def index(done: nil, limit: 50)
    @todos.list(done:, limit:)
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record | Responses::NotFound
  def show(id:)
    @todos.find(id) || not_found
  end

  # @rbs body: NewTodo
  # @rbs return: Responses::Created[Todos::Record] | Responses::NotFound | Responses::Unprocessable
  def create(body:)
    todo = @todos.create(title: body.title, priority: body.priority, due_on: body.due_on, list_id: body.list_id)
    case todo
    when Todos::Record then created todo
    when :no_such_list then not_found "List #{body.list_id} doesn't exist"
    else unprocessable 'A title needs 1 to 200 characters'
    end
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record | Responses::NotFound
  def complete(id:)
    @todos.complete(id) || not_found
  end

  # @rbs id: Integer
  # @rbs return: Responses::NoContent | Responses::NotFound
  def destroy(id:)
    @todos.delete(id).zero? ? not_found : no_content
  end
end
