# frozen_string_literal: true

require_relative "todo"

class TodoStore
  # @rbs @lock: Thread::Mutex
  # @rbs @todos: Hash[Integer, Todo]
  # @rbs @last_id: Integer

  # @rbs return: void
  def initialize
    # Every request shares the one API object, and so this store, from whichever
    # thread or fiber serves it.
    @lock = Mutex.new
    @todos = {}
    @last_id = 0
  end

  # @rbs done: bool?
  # @rbs limit: Integer
  # @rbs return: Array[Todo]
  def list(done:, limit:)
    todos = @lock.synchronize { @todos.values }
    todos.reverse.select { |todo| done.nil? || todo.done == done }.first(limit).freeze
  end

  # @rbs id: Integer
  # @rbs return: Todo?
  def find(id) = @lock.synchronize { @todos[id] }

  # @rbs title: String
  # @rbs priority: :low | :normal | :high
  # @rbs due_on: Date?
  # @rbs return: Todo
  def create(title:, priority:, due_on:)
    @lock.synchronize do
      @last_id += 1
      @todos[@last_id] = Todo.new(id: @last_id, title:, priority:, due_on:, done: false)
    end
  end

  # @rbs id: Integer
  # @rbs return: Todo?
  def complete(id)
    @lock.synchronize do
      todo = @todos[id]
      @todos[id] = todo.with(done: true) if todo
    end
  end

  # @rbs id: Integer
  # @rbs return: Todo?
  def delete(id) = @lock.synchronize { @todos.delete(id) }
end
