# frozen_string_literal: true

require "test_helper"

describe TodoStore do
  let(:store) { TodoStore.new }

  def create(title = "Ship it") = store.create(title:, priority: :normal, due_on: nil)

  describe "#list" do
    it "lists the newest todo first" do
      %w[First Second].each { |title| create(title) }

      assert_equal %w[Second First], store.list(done: nil, limit: 50).map(&:title)
    end

    it "lists only done todos when done is true" do
      create("Open")
      store.complete(create("Done").id)

      assert_equal %w[Done], store.list(done: true, limit: 50).map(&:title)
    end

    it "lists only open todos when done is false" do
      create("Open")
      store.complete(create("Done").id)

      assert_equal %w[Open], store.list(done: false, limit: 50).map(&:title)
    end

    it "lists at most limit todos" do
      %w[First Second Third].each { |title| create(title) }

      assert_equal %w[Third Second], store.list(done: nil, limit: 2).map(&:title)
    end

    it "returns a frozen list" do
      assert_predicate store.list(done: nil, limit: 50), :frozen?
    end
  end

  describe "#find" do
    it "finds a todo by its id" do
      todo = create

      assert_equal todo, store.find(todo.id)
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil store.find(1)
    end
  end

  describe "#create" do
    it "creates an open todo with the next id" do
      create
      todo = store.create(title: "Buy milk", priority: :high, due_on: Date.new(2026, 12, 1))

      assert_equal Todo.new(id: 2, title: "Buy milk", priority: :high, due_on: Date.new(2026, 12, 1), done: false), todo
    end

    it "keeps the todo" do
      todo = create

      assert_equal [todo], store.list(done: nil, limit: 50)
    end
  end

  describe "#complete" do
    it "returns the todo, done" do
      todo = create

      assert_equal todo.with(done: true), store.complete(todo.id)
    end

    it "keeps the todo done" do
      todo = create
      store.complete(todo.id)

      assert store.find(todo.id).done
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil store.complete(1)
    end
  end

  describe "#delete" do
    it "returns the deleted todo" do
      todo = create

      assert_equal todo, store.delete(todo.id)
    end

    it "forgets the todo" do
      todo = create
      store.delete(todo.id)

      assert_nil store.find(todo.id)
    end

    it "returns nil for a todo that doesn't exist" do
      assert_nil store.delete(1)
    end
  end
end
