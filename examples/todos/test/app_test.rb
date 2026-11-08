# frozen_string_literal: true

require "test_helper"

# Every test shares App, and so its todos, so each one checks only the todos
# it creates.
describe "App" do
  let(:client) { Skyward::Test.client(App) }

  def create(title = "Ship it", priority: "normal", due_on: nil)
    client.post("/todos", json: { title:, priority:, due_on: })
  end

  def completed = client.post("/todos/#{create.json[:id]}/complete").json

  def ids(path) = client.get(path).json.map { |todo| todo[:id] }

  describe "GET /up" do
    it "says the app is up" do
      assert_equal({ status: "ok" }, client.get("/up").json)
    end
  end

  describe "GET /todos" do
    it "lists the newest todo first" do
      id = create.json[:id]

      assert_equal id, ids("/todos").first
    end

    it "lists only done todos when done is true" do
      open = create.json[:id]
      done = completed[:id]

      assert_includes ids("/todos?done=true"), done
      refute_includes ids("/todos?done=true"), open
    end

    it "leaves done todos out when done is false" do
      id = completed[:id]

      refute_includes ids("/todos?done=false"), id
    end

    it "lists at most limit todos" do
      2.times { create }

      assert_equal 1, ids("/todos?limit=1").size
    end
  end

  describe "GET /todos/:id" do
    it "answers the todo" do
      todo = create.json

      assert_equal todo, client.get("/todos/#{todo[:id]}").json
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_equal 404, client.get("/todos/0").status
    end
  end

  describe "POST /todos" do
    it "answers 201" do
      assert_equal 201, create.status
    end

    it "answers the new todo" do
      todo = create("Buy milk", priority: "high", due_on: "2026-12-01").json

      assert_equal({ title: "Buy milk", priority: "high", due_on: "2026-12-01", done: false }, todo.except(:id))
    end

    it "rejects a priority that doesn't exist" do
      response = create(priority: "urgent")

      assert_equal 422, response.status
      assert_equal "body.priority", response.json[:errors].first[:at]
    end
  end

  describe "POST /todos/:id/complete" do
    it "answers the todo, done" do
      assert completed[:done]
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_equal 404, client.post("/todos/0/complete").status
    end
  end

  describe "DELETE /todos/:id" do
    it "answers 204" do
      assert_equal 204, client.delete("/todos/#{create.json[:id]}").status
    end

    it "deletes the todo" do
      id = create.json[:id]
      client.delete("/todos/#{id}")

      assert_equal 404, client.get("/todos/#{id}").status
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_equal 404, client.delete("/todos/0").status
    end
  end

  describe "GET /openapi.json" do
    it "documents every endpoint" do
      paths = client.get("/openapi.json").json[:paths].keys

      assert_equal %i[/up /todos /todos/{id} /todos/{id}/complete], paths
    end
  end

  describe "GET /docs" do
    it "serves the API reference" do
      assert_includes client.get("/docs").body, "<title>Todos</title>"
    end
  end
end
