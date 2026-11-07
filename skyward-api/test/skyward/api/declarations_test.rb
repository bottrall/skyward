# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Declarations do
  let(:api) { Class.new { extend Skyward::API::Declarations } }

  def route(verb, path, to, summary: nil, description: nil)
    Skyward::API::Route.new(verb:, path:, to:, summary:, description:)
  end

  def refusal
    yield
    nil
  rescue ArgumentError => e
    e.message
  end

  describe "#routes" do
    it "is empty until a route is declared" do
      assert_empty api.routes
    end
  end

  describe "#class_description" do
    it "is nil until a description is declared" do
      assert_nil api.class_description
    end
  end

  describe "#description" do
    it "refuses a second description" do
      api.description "Things to do."
      message = refusal { api.description "Things to avoid." }

      assert_equal "#{api} already has a description", message
    end

    it "sets the class's description" do
      api.description "Things to do."

      assert_equal "Things to do.", api.class_description
    end

    it "keeps a frozen copy" do
      api.description(+"Things to do.")

      assert_predicate api.class_description, :frozen?
    end
  end

  describe "#get" do
    it "declares a GET route" do
      api.get "/", to: :index

      assert_equal [route(:get, "/", :index)], api.routes
    end

    it "keeps the summary and description" do
      api.get "/", to: :index, summary: "List todos.", description: "Newest first."

      assert_equal [route(:get, "/", :index, summary: "List todos.", description: "Newest first.")], api.routes
    end
  end

  describe "#post" do
    it "declares a POST route" do
      api.post "/", to: :create

      assert_equal [route(:post, "/", :create)], api.routes
    end
  end

  describe "#put" do
    it "declares a PUT route" do
      api.put "/:id", to: :replace

      assert_equal [route(:put, "/:id", :replace)], api.routes
    end
  end

  describe "#patch" do
    it "declares a PATCH route" do
      api.patch "/:id", to: :update

      assert_equal [route(:patch, "/:id", :update)], api.routes
    end
  end

  describe "#delete" do
    it "declares a DELETE route" do
      api.delete "/:id", to: :destroy

      assert_equal [route(:delete, "/:id", :destroy)], api.routes
    end
  end

  describe "inheriting" do
    let(:parent) { api.tap { |parent| parent.get "/", to: :index } }

    it "starts a subclass with its parent's routes" do
      assert_equal parent.routes, Class.new(parent).routes
    end

    it "adds a subclass's routes after its parent's" do
      child = Class.new(parent)
      child.get "/:id", to: :show

      assert_equal [route(:get, "/", :index), route(:get, "/:id", :show)], child.routes
    end

    it "leaves the parent's routes alone" do
      Class.new(parent).get "/:id", to: :show

      assert_equal [route(:get, "/", :index)], parent.routes
    end

    it "doesn't pass on the parent's description" do
      parent.description "Things to do."

      assert_nil Class.new(parent).class_description
    end

    it "starts a redefined class without the old class's routes" do
      namespace = Module.new
      namespace.const_set(:Todos, Class.new(parent) { get "/:id", to: :show })
      namespace.send(:remove_const, :Todos)
      namespace.const_set(:Todos, Class.new(parent))

      assert_equal [route(:get, "/", :index)], namespace::Todos.routes
    end
  end

  describe "declaring" do
    it "declares nothing when it refuses" do
      refusal { api.get "todos", to: :index }

      assert_empty api.routes
    end

    it "keeps routes in the order they're declared" do
      api.post "/", to: :create
      api.get "/", to: :index

      assert_equal [route(:post, "/", :create), route(:get, "/", :index)], api.routes
    end

    it "lets two routes name the same method" do
      api.put "/:id", to: :update
      api.patch "/:id", to: :update

      assert_equal [route(:put, "/:id", :update), route(:patch, "/:id", :update)], api.routes
    end

    it "keeps frozen copies of the strings" do
      api.get(+"/:id", to: :show, summary: +"Fetch a todo.", description: +"By its ID.")

      assert(api.routes.first.to_h.values.all?(&:frozen?))
    end

    it "keeps the routes in a frozen array" do
      api.get "/", to: :index

      assert_predicate api.routes, :frozen?
    end

    it "refuses a path that isn't a String" do
      message = refusal { api.get :todos, to: :index }

      assert_equal "#{api} GET :todos: the path must be a String that starts with /", message
    end

    it "refuses a path that doesn't start with /" do
      message = refusal { api.get "todos", to: :index }

      assert_equal %(#{api} GET "todos": the path must be a String that starts with /), message
    end

    it "accepts a path parameter with underscores and digits" do
      api.get "/:_todo_id2", to: :show

      assert_equal [route(:get, "/:_todo_id2", :show)], api.routes
    end

    it "refuses a path parameter that isn't a valid keyword name" do
      message = refusal { api.get "/:2nd", to: :show }

      assert_equal %(#{api} GET "/:2nd": path parameter "2nd" isn't a valid keyword name), message
    end

    it "refuses a path parameter with no name" do
      message = refusal { api.get "/:", to: :show }

      assert_equal %(#{api} GET "/:": path parameter "" isn't a valid keyword name), message
    end

    it "refuses a path parameter used more than once" do
      message = refusal { api.get "/:id/:id", to: :show }

      assert_equal %(#{api} GET "/:id/:id": path parameter "id" is used more than once), message
    end

    it "refuses a method name that isn't a Symbol" do
      message = refusal { api.get "/", to: "index" }

      assert_equal %(#{api} GET "/": to: must be a Symbol, got "index"), message
    end
  end
end
