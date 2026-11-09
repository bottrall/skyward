# frozen_string_literal: true

require "test_helper"

describe Todos::Service do
  service = Todos::Service

  def create(title = "Ship it", list_id: nil) = Todos::Service.create(title:, priority: :normal, due_on: nil, list_id:)

  describe ".list" do
    it "lists the newest todo first" do
      %w[First Second].each { |title| create(title) }

      assert_equal %w[Second First], service.list(done: nil, limit: 50).map(&:title)
    end

    it "lists only done todos when done is true" do
      create("Open")
      service.complete(create("Done").id)

      assert_equal %w[Done], service.list(done: true, limit: 50).map(&:title)
    end

    it "lists only open todos when done is false" do
      create("Open")
      service.complete(create("Done").id)

      assert_equal %w[Open], service.list(done: false, limit: 50).map(&:title)
    end

    it "lists at most limit todos" do
      %w[First Second Third].each { |title| create(title) }

      assert_equal %w[Third Second], service.list(done: nil, limit: 2).map(&:title)
    end
  end

  describe ".find" do
    it "finds a todo by its id" do
      todo = create

      assert_equal todo, service.find(todo.id)
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil service.find(0)
    end
  end

  describe ".create" do
    it "creates an open todo" do
      todo = service.create(title: "Buy milk", priority: :high, due_on: Date.new(2026, 12, 1), list_id: nil)

      assert_equal(
        { list_id: nil, title: "Buy milk", priority: :high, due_on: Date.new(2026, 12, 1), done: false },
        todo.to_h.except(:id)
      )
    end

    it "keeps the todo" do
      todo = create

      assert_equal [todo], service.list(done: nil, limit: 50)
    end

    it "puts the todo on its list" do
      list = Lists::Record.insert!(name: "Home")

      assert_equal list.id, create(list_id: list.id).list_id
    end

    it "returns :no_such_list for a list that doesn't exist" do
      assert_equal :no_such_list, create(list_id: 0)
    end

    it "returns :invalid_title for a title that's empty" do
      assert_equal :invalid_title, create("")
    end
  end

  describe ".complete" do
    it "returns the todo, done" do
      todo = create

      assert_equal todo.with(done: true), service.complete(todo.id)
    end

    it "keeps the todo done" do
      todo = create
      service.complete(todo.id)

      assert service.find(todo.id).done
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil service.complete(0)
    end
  end

  describe ".delete" do
    it "returns the deleted todo" do
      todo = create

      assert_equal todo, service.delete(todo.id)
    end

    it "forgets the todo" do
      todo = create
      service.delete(todo.id)

      assert_nil service.find(todo.id)
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil service.delete(0)
    end
  end
end
