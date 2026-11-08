# frozen_string_literal: true

# Signed in sig/boot_fixtures.rbs, except Unsigned and the classes refused
# before their signature is read: Unrouted, Private and Protected. Each class
# that fails to boot has one problem.
module BootFixtures
  Todo = Data.define(:id, :title)
  User = Data.define(:id, :name, :password_hash)
  Holder = Class.new
  Node = Class.new

  Hello = Class.new(Skyward::API) do
    get "/:name", to: :greet

    def greet(name:) = { message: "Hello, #{name}" }
  end

  Failing = Class.new(Skyward::API) do
    get "/", to: :fail

    def fail = raise("todo 42 is secret")
  end

  Todos = Class.new(Skyward::API) do
    get "/", to: :index, summary: "List todos."
    get "/done/", to: :index
    get "/:id", to: :show
    post "/", to: :create
    delete "/:id", to: :destroy

    def index(done: nil, tags: []) = { done:, tags: }

    def show(id:) = { id: }

    def create(body:) = body

    def destroy(id:) = { id: }
  end

  NewForm = Class.new(Skyward::API) do
    get "/new", to: :new_form

    def new_form = {}
  end

  StaticFirst = Class.new(Skyward::API) do
    get "/new", to: :new_form
    get "/:id", to: :show

    def new_form = {}

    def show(id:) = { id: }
  end

  RootLast = Class.new(Skyward::API) do
    get "/:id", to: :show
    get "/", to: :index

    def show(id:) = { id: }

    def index = []
  end

  StaticLast = Class.new(Skyward::API) do
    get "/:id", to: :show
    get "/new", to: :new_form

    def show(id:) = { id: }

    def new_form = {}
  end

  SameShape = Class.new(Skyward::API) do
    get "/:id", to: :show
    get "/:todo_id", to: :find

    def show(id:) = { id: }

    def find(todo_id:) = { todo_id: }
  end

  Summarised = Class.new(Skyward::API) do
    get "/", to: :index, summary: "List todos.\nNewest first."

    def index = []
  end

  Unrouted = Class.new(Skyward::API) do
    get "/", to: :index
  end

  Private = Class.new(Skyward::API) do
    get "/", to: :index

    def index = []
    private :index
  end

  Protected = Class.new(Skyward::API) do
    get "/", to: :index

    def index = []
    protected :index
  end

  Unsigned = Class.new(Skyward::API) do
    get "/", to: :index

    def index = []
  end

  UnsignedMethod = Class.new(Skyward::API) do
    get "/", to: :index

    def index = []
  end

  Positional = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(id) = { id: }
  end

  KeywordRest = Class.new(Skyward::API) do
    get "/", to: :index

    def index(**filters) = filters
  end

  Renamed = Class.new(Skyward::API) do
    get "/", to: :index

    def index(limit:) = { limit: }
  end

  MadeOptional = Class.new(Skyward::API) do
    get "/", to: :index

    def index(limit: 50) = { limit: }
  end

  SignedPositionally = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(id:) = { id: }
  end

  SignedUntyped = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(id:) = { id: }
  end

  Unnamed = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(todo_id:) = { todo_id: }
  end

  TupleQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(range:) = { range: }
  end

  HashBody = Class.new(Skyward::API) do
    post "/", to: :create

    def create(body:) = body
  end

  ArrayPath = Class.new(Skyward::API) do
    get "/:ids", to: :show

    def show(ids:) = { ids: }
  end

  ClassPath = Class.new(Skyward::API) do
    get "/:todo", to: :show

    def show(todo:) = { todo: }
  end

  RecordQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(filter:) = { filter: }
  end

  NullableClassQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(like: nil) = { like: }
  end

  UnionQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(near:) = { near: }
  end

  NestedArrayQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(grid:) = { grid: }
  end

  HashReturn = Class.new(Skyward::API) do
    get "/", to: :index

    def index = {}
  end

  SelfReferring = Class.new(Skyward::API) do
    get "/", to: :index

    def index = {}
  end

  Responding = Class.new(Skyward::API) do
    get "/:id", to: :show
    get "/users/:id", to: :user
    get "/users/:id/todo", to: :misfit
    post "/", to: :create
    delete "/:id", to: :destroy

    def show(id:) = not_found("Todo #{id} does not exist")

    # Path parameters arrive as Strings until coercion lands.
    def user(id:) = User.new(id: Integer(id), name: "Ada", password_hash: "$2a$12$secret")

    def misfit(id:) = user(id:)

    def create(body:) = created(Todo.new(id: 1, **body), headers: { "location" => "/1" })

    def destroy(id:) = conflict("Todo #{id} is in use")
  end

  CreatedHash = Class.new(Skyward::API) do
    post "/", to: :create

    def create = created({})
  end

  CreatedBare = Class.new(Skyward::API) do
    post "/", to: :create

    def create = created({})
  end
end
