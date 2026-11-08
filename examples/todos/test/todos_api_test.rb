# frozen_string_literal: true

require "test_helper"

describe TodosAPI do
  let(:todos) { TodoStore.new }
  let(:api) { TodosAPI.new(todos:) }

  def create(title = "Ship it") = todos.create(title:, priority: :normal, due_on: nil)

  describe "#index" do
    it "lists 50 todos, open or done, by default" do
      51.times { create }
      todos.complete(51)

      assert_equal todos.list(done: nil, limit: 50), api.index
    end

    it "lists only done todos when done is true" do
      create("Open")
      todos.complete(create("Done").id)

      assert_equal %w[Done], api.index(done: true).map(&:title)
    end

    it "lists at most limit todos" do
      %w[First Second].each { |title| create(title) }

      assert_equal %w[Second], api.index(limit: 1).map(&:title)
    end
  end

  describe "#show" do
    it "answers the todo" do
      todo = create

      assert_equal todo, api.show(id: todo.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::NotFound, api.show(id: 1)
    end
  end

  describe "#create" do
    it "answers the new todo, created" do
      due_on = Date.new(2026, 12, 1)
      body = NewTodo.new(title: "Buy milk", priority: :high, due_on:)

      assert_equal Todo.new(id: 1, title: "Buy milk", priority: :high, due_on:, done: false), api.create(body:).value
    end
  end

  describe "#complete" do
    it "answers the todo, done" do
      todo = create

      assert_equal todo.with(done: true), api.complete(id: todo.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::NotFound, api.complete(id: 1)
    end
  end

  describe "#destroy" do
    it "answers 204 once the todo is deleted" do
      assert_instance_of Skyward::NoContent, api.destroy(id: create.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::NotFound, api.destroy(id: 1)
    end
  end
end
