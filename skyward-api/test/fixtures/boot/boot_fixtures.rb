# frozen_string_literal: true

# Signed in sig/boot_fixtures.rbs, except Unsigned, UnsignedPositional, UnsignedProvider, ModuleProvider,
# ClassProvider, UnsignedProvided and the classes refused before their signature is read: Unrouted, Private and
# Protected. Each class that fails to boot has one problem.
module BootFixtures
  Todo = Data.define(:id, :title)
  User = Data.define(:id, :name, :password_hash)
  Draft = Data.define(:title, :priority, :due_on)
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

    def show(id:) = Todo.new(id:, title: "Ship it")

    def create(body:) = Todo.new(id: 1, title: body[:title])

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
    get "/:name", to: :greet

    def greet(name:, shout: "false", request: nil) = { name:, shout:, request: }
  end

  UnsignedMethod = Class.new(Skyward::API) do
    get "/", to: :index

    def index = []
  end

  UnsignedPositional = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(id) = { id: }
  end

  Inlined = Class.new(Skyward::API) do
    get "/:name", to: :greet

    def greet(name:, shout: "false", request: nil) = { name:, shout:, request: }
  end

  UntypedKeyword = Class.new(Skyward::API) do
    get "/:id", to: :show

    def show(id:) = Todo.new(id: 1, title: id)
  end

  NullableUntypedKeyword = Class.new(Skyward::API) do
    get "/", to: :index

    def index(limit: nil) = Todo.new(id: 1, title: limit.to_s)
  end

  NestedUntyped = Class.new(Skyward::API) do
    get "/", to: :index

    def index(tags: []) = tags
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

  HashPath = Class.new(Skyward::API) do
    get "/:scores", to: :show

    def show(scores:) = { scores: }
  end

  RecordQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(filter:) = { filter: }
  end

  HashQuery = Class.new(Skyward::API) do
    get "/", to: :index

    def index(scores: nil) = { scores: }
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

  Requesting = Class.new(Skyward::API) do
    get "/", to: :index
    get "/:id", to: :show

    def index(request:)
      {
        authorization: request.headers["authorization"],
        session: request.cookies["session"],
        ip: request.ip,
        request_id: request.request_id
      }
    end

    def show(id:, request: nil) = Todo.new(id:, title: request.request_id)
  end

  MistypedRequest = Class.new(Skyward::API) do
    get "/", to: :index

    def index(request:) = { request: }
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

    def user(id:) = User.new(id:, name: "Ada", password_hash: "$2a$12$secret")

    def misfit(id:) = user(id:)

    def create(body:) = created(Todo.new(id: 1, **body), headers: { "location" => "/1" })

    def destroy(id:) = conflict("Todo #{id} is in use")
  end

  Racking = Class.new(Skyward::API) do
    get "/stream", to: :stream
    get "/letters", to: :letters
    get "/written", to: :written
    get "/:id", to: :download

    def stream
      chunks = Enumerator.new do |out|
        out << "first\n"
        out << "second\n"
      end
      [200, { "content-type" => "text/plain" }, chunks]
    end

    def letters = %w[a b c]

    def written = [204, {}, []]

    def download(id:) = not_found("Todo #{id} does not exist")
  end

  # Every kind of route the OpenAPI document describes, each method routed once.
  Documented = Class.new(Skyward::API) do
    description "Things to do."

    get "/", to: :index, summary: "List todos."
    get "/:id", to: :show, summary: "Fetch a todo.", description: "It's *Markdown*."
    post "/", to: :create
    delete "/:id", to: :destroy
    get "/:id/elsewhere", to: :moved
    get "/:id/export", to: :export

    def index(done: nil, tags: [], since: nil) = [{ done:, tags:, since: }]

    def show(id:) = not_found("Todo #{id} does not exist")

    def create(body:) = created(body)

    def destroy(id:) = not_found("Todo #{id} does not exist")

    def moved(id:) = redirect("/#{id}")

    def export(id:) = [200, { "content-type" => "text/csv" }, ["#{id}\n"]]
  end

  CreatedHash = Class.new(Skyward::API) do
    post "/", to: :create

    def create = created({})
  end

  CreatedBare = Class.new(Skyward::API) do
    post "/", to: :create

    def create = created({})
  end

  CurrentUser = Class.new do
    def call(request)
      return Skyward.unauthorized("Sign in first") unless request.headers["authorization"] == "Bearer ada"

      User.new(id: 1, name: "Ada", password_hash: "$2a$12$secret")
    end
  end

  Sessions = Class.new do
    def user_for(request) = CurrentUser.new.call(request)
  end

  Visitor = Class.new do
    def call(_request) = nil
  end

  Guard = Class.new do
    def call(_request) = Skyward.forbidden("Admins only")
  end

  UnsignedProvider = Class.new do
    def call(_request) = "anyone"
  end

  ModuleProvider = Module.new do
    extend self

    def call(_request) = "anyone"
  end

  ClassProvider = Class.new do
    def self.call(_request) = "anyone"
  end

  Authenticated = Class.new(Skyward::API) do
    get "/me", to: :me
    get "/todos", to: :index

    def me(current_user:) = current_user

    def index(tenant:, current_user:, limit: 50) = [Todo.new(id: limit, title: "#{tenant} #{current_user.name}")]
  end

  Visiting = Class.new(Skyward::API) do
    get "/", to: :index

    def index(visitor:) = [visitor].compact
  end

  MistypedUser = Class.new(Skyward::API) do
    get "/", to: :index

    def index(current_user:) = [current_user]
  end

  Guarded = Class.new(Skyward::API) do
    get "/", to: :index

    def index(admin:) = [admin]
  end

  ProvidedPath = Class.new(Skyward::API) do
    get "/:current_user", to: :show

    def show(current_user:) = Todo.new(id: 1, title: current_user)
  end

  UnsignedProvided = Class.new(Skyward::API) do
    get "/", to: :index

    def index(current_user:, limit: 50) = [Todo.new(id: limit, title: current_user.name)]
  end

  UntypedProvided = Class.new(Skyward::API) do
    get "/", to: :index

    def index(current_user:, visitor:) = [Todo.new(id: current_user.id, title: visitor.to_s)]
  end
end
