# frozen_string_literal: true

require "test_helper"

describe Todos::API do
  let(:todos) { Todos::Service }
  let(:api) { Todos::API.new(todos:) }

  def create(title = "Ship it") = todos.create(title:, priority: :normal, due_on: nil, list_id: nil)

  def new_todo(title: "Ship it", due_on: nil, list_id: nil)
    Todos::API::NewTodo.new(title:, priority: :high, due_on:, list_id:)
  end

  describe "#index" do
    it "lists 50 todos, open or done, by default" do
      50.times { create }
      todos.complete(create.id)

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
      assert_instance_of Skyward::API::Responses::NotFound, api.show(id: 0)
    end
  end

  describe "#create" do
    it "answers the new todo, created" do
      list = Lists::Record.into(Lists::Record).insert!(name: "Home")
      response = api.create(body: new_todo(title: "Buy milk", due_on: Date.new(2026, 12, 1), list_id: list.id))

      assert_instance_of Skyward::API::Responses::Created, response
      assert_equal(
        { list_id: list.id, title: "Buy milk", priority: :high, due_on: Date.new(2026, 12, 1), done: false },
        response.value.to_h.except(:id)
      )
    end

    it "answers 404 for a list that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.create(body: new_todo(list_id: 0))
    end

    it "answers 422 for a title that's empty" do
      assert_instance_of Skyward::API::Responses::Unprocessable, api.create(body: new_todo(title: ""))
    end
  end

  describe "#complete" do
    it "answers the todo, done" do
      todo = create

      assert_equal todo.with(done: true), api.complete(id: todo.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.complete(id: 0)
    end
  end

  describe "#destroy" do
    it "answers 204 once the todo is deleted" do
      assert_instance_of Skyward::API::Responses::NoContent, api.destroy(id: create.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.destroy(id: 0)
    end
  end
end
