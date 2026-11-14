# frozen_string_literal: true

require "test_helper"

describe Bench::TodosAPI do
  let(:todo) { Bench::TodosAPI::Todo.new(id: 1, title: "Ship it", done: false, due_on: nil, tags: []) }
  let(:api) { Bench::TodosAPI.new(todos: { 1 => todo }) }

  describe "#show" do
    it "answers the todo" do
      assert_equal todo, api.show(id: 1)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.show(id: 2)
    end
  end

  describe "#create" do
    it "answers the new todo, created, with the next id" do
      body = Bench::TodosAPI::NewTodo.new(title: "Buy milk", done: true, due_on: Date.new(2026, 12, 1), tags: %w[home])

      assert_equal todo.with(id: 2, title: "Buy milk", done: true, due_on: Date.new(2026, 12, 1), tags: %w[home]),
                   api.create(body:).value
    end
  end
end
