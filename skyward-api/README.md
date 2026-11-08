# Skyward API

> [!CAUTION]
> **Work in progress: Skyward API is barely started.** Version 0.1 is a skeleton. The gems install and load, but only the parts listed under [Status](#status) are built. This README is the spec for what's coming, not documentation of what exists. Don't depend on it yet.

A small, fast Ruby web framework where **an endpoint is a method**.

Its inputs are keyword arguments. Its response is the return value. Add a type signature and Skyward API uses it to coerce and validate the request, check your code with Steep, and write your OpenAPI docs for you. Leave the signature off and it's still just Ruby.

Skyward API is half of Skyward. The other half is [Skyward ORM](../skyward-orm/README.md), but each works without the other.

```ruby
# config.ru
require "skyward/api"

class Hello < Skyward::API
  get "/hello/:name", to: :greet

  def greet(name:, shout: "false")
    message = "Hello, #{name}"
    { message: shout == "true" ? message.upcase : message }
  end
end

run Skyward.app { |app| app.mount Hello.new }
```

```sh
$ skyward serve
$ curl localhost:9292/hello/ruby?shout=true
{"message":"HELLO, RUBY"}
```

That's the whole framework. The rest of this README is detail.

---

## Contents

- [Install](#install)
- [Endpoints](#endpoints)
- [Inputs](#inputs)
- [Responses](#responses)
- [Types: the bonus that pays rent](#types-the-bonus-that-pays-rent)
- [OpenAPI docs](#openapi-docs)
- [Building an app](#building-an-app)
- [Providers](#providers)
- [Errors](#errors)
- [Testing](#testing)
- [Production](#production)
- [CLI](#cli)
- [Coming from…](#coming-from)
- [Design principles](#design-principles)
- [Status](#status)

---

## Install

```ruby
# Gemfile
gem "skyward-api"
```

Skyward API supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026), and runs on any Rack 3 server. It recommends [Falcon](https://github.com/socketry/falcon) or Puma. `skyward serve` runs Falcon, so add `gem "falcon"` to use it.

---

## Endpoints

An endpoint is a public method. The class lists its routes at the top, and each route names the method it calls.

```ruby
class TodosAPI < Skyward::API
  get "/",    to: :index, summary: "List todos, newest first."
  get "/:id", to: :show,  summary: "Fetch a single todo."

  def initialize(todos:)
    super()
    @todos = todos
  end

  def index(done: nil, limit: "50")
    @todos.list(done:, limit: Integer(limit))
  end

  def show(id:)
    @todos.find(Integer(id)) || not_found
  end
end
```

- `Skyward::API` gives the class `get`, `post`, `put`, `patch` and `delete`, and gives its instances the response helpers below. It has no initializer or state of its own, so the initializer is yours, and so are the instance variables.
- Routes go at the top of the class, so it opens with a table of everything it serves. Each names its method with `to:`, and two routes can name the same one. Below the routes, an endpoint is an ordinary method, written and typed like any other.
- A route that names a method the class doesn't have, or a path parameter the method doesn't take, fails at boot.
- An API class doesn't know where it lives. You choose the prefix when you mount it (`at: "/todos"`).
- Each API object is created **once**, at boot, and shared by every request. Per-request data arrives as arguments, never as instance state, so your handlers are thread- and fiber-safe by default.
- A route's `summary:` is its documentation, in the [OpenAPI docs](#openapi-docs). It's optional, and it's a plain Ruby string: Skyward API never reads comments.

---

## Inputs

Skyward API fills each keyword argument by its name:

| Keyword                                         | Filled from                                                                  |
| ----------------------------------------------- | ---------------------------------------------------------------------------- |
| a path parameter (`id:` for `/:id`)             | the URL path                                                                 |
| `body:`                                         | the parsed JSON request body                                                 |
| `request:`                                      | the raw `Skyward::Request` (an escape hatch for headers, cookies and the IP) |
| a [provided](#providers) name (`current_user:`) | your provider                                                                |
| anything else                                   | the query string                                                             |

Ruby already has syntax for required and optional, so Skyward API uses it. A keyword with no default is required: if it's missing, the request fails with a 422 before your method runs. A keyword with a default is optional.

Without types, path and query values arrive as `String`s and `body:` arrives as a `Hash` with symbol keys. That makes it a good fit for pattern matching:

```ruby
post "/", to: :create

def create(body:)
  case body
  in { title: String => title } then created @todos.create(title:)
  else unprocessable "title is required"
  end
end
```

---

## Responses

Return a value and Skyward API turns it into a response. There's no `render`, no `halt`, and nothing is raised for an ordinary 404.

| Return                                             | Status             | Helper                    |
| -------------------------------------------------- | ------------------ | ------------------------- |
| a `Hash`, `Array`, `Data`, or anything with `to_h` | 200, JSON          | —                         |
| `Skyward::Created[T]`                              | 201, JSON          | `created(value)`          |
| `Skyward::NoContent`                               | 204                | `no_content`              |
| `Skyward::BadRequest`                              | 400, problem+json  | `bad_request(detail)`     |
| `Skyward::Unauthorized`                            | 401, problem+json  | `unauthorized(detail)`    |
| `Skyward::Forbidden`                               | 403, problem+json  | `forbidden(detail)`       |
| `Skyward::NotFound`                                | 404, problem+json  | `not_found(detail = nil)` |
| `Skyward::Conflict`                                | 409, problem+json  | `conflict(detail)`        |
| `Skyward::Unprocessable`                           | 422, problem+json  | `unprocessable(detail)`   |
| `Skyward::Redirect`                                | 303 (or `status:`) | `redirect(to)`            |
| a Rack triple `[status, headers, body]`            | as given           | —                         |

Every helper takes `headers:`:

```ruby
created todo, headers: { "location" => "/todos/#{todo.id}" }
```

Error responses use [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) `application/problem+json`:

```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Todo 42 does not exist"
}
```

A Rack triple is the escape hatch for anything a value can't express: streaming, files, or a content type other than JSON. Its status, headers and body are sent as given, so a body that streams through `each` or `call` works. Rack 3 wants lowercase header names, and Skyward API doesn't rewrite them. A typed endpoint sends a triple only when its return type says so, with `Skyward::rack`, which is `[Integer, Hash[String, String], untyped]`:

```ruby
# @rbs id: Integer
# @rbs return: Skyward::rack | NotFound
def export(id:)
  todo = @todos.find(id)
  todo ? [200, { "content-type" => "text/csv" }, [todo.to_csv]] : not_found
end
```

Nothing checks what a triple sends: that's the point of an escape hatch, and why it's opt-in through the return type. An `Array[T]` return is always JSON, even with three items.

---

## Types: the bonus that pays rent

Everything above works without types. Add a signature and it does more:

- **Coercion.** `"42"` in the path becomes `42` when the signature says `Integer`.
- **Validation.** A body that doesn't match its type is rejected with a 422 that says exactly what was wrong, before your method runs.
- **Docs.** The signature becomes the OpenAPI operation, including every possible response.
- **Checking.** Steep checks your handlers like any other Ruby code, because they _are_ ordinary Ruby code.

Signatures are plain [RBS](https://github.com/ruby/rbs). Write them inline with [rbs-inline](https://github.com/soutaro/rbs-inline), or in `sig/*.rbs` files. Skyward API reads both, from the `.rbs` files under `sig/` (or the directory you pass as `Skyward.app(signatures:)`), so run rbs-inline before you boot. There's no schema DSL to learn and nothing to keep in sync: **the type you write for Steep is the API contract.**

```ruby
# rbs_inline: enabled
# @rbs use Skyward::*

Todo = Data.define(
  :id,        #: Integer
  :title,     #: String
  :priority,  #: :low | :normal | :high
  :due_on,    #: Date?
  :done       #: bool
)

NewTodo = Data.define(
  :title,     #: String
  :priority,  #: :low | :normal | :high
  :due_on     #: Date?
)

class TodosAPI < Skyward::API
  description "Things to do, and the satisfaction of ticking them off."

  get    "/",             to: :index,    summary: "List todos, newest first."
  get    "/:id",          to: :show,     summary: "Fetch a single todo."
  post   "/",             to: :create,   summary: "Create a todo."
  post   "/:id/complete", to: :complete, summary: "Mark a todo as done.", description: <<~TEXT
    Marking a todo that's already done is fine: it stays done, and the
    response is the same.
  TEXT
  delete "/:id",          to: :destroy,  summary: "Delete a todo."

  # @rbs @todos: TodoStore

  # @rbs todos: TodoStore
  # @rbs return: void
  def initialize(todos:)
    super()
    @todos = todos
  end

  # @rbs done: bool?
  # @rbs limit: Integer
  # @rbs return: Array[Todo]
  def index(done: nil, limit: 50)
    @todos.list(done:, limit:)
  end

  # @rbs id: Integer
  # @rbs return: Todo | NotFound
  def show(id:)
    @todos.find(id) || not_found
  end

  # @rbs body: NewTodo
  # @rbs return: Created[Todo]
  def create(body:)
    created @todos.create(**body.to_h)
  end

  # @rbs id: Integer
  # @rbs return: Todo | NotFound
  def complete(id:)
    @todos.complete(id) || not_found
  end

  # @rbs id: Integer
  # @rbs return: NoContent | NotFound
  def destroy(id:)
    @todos.delete(id) ? no_content : not_found
  end
end
```

`body:` is now a real `NewTodo`, not a `Hash`. `id:` is an `Integer`. The union return type `Todo | NotFound` tells the docs this endpoint can answer with a 200 or a 404. `# @rbs use Skyward::*` at the top of the file lets the signatures say `Created[Todo]`, `NotFound` and `NoContent` without the `Skyward::` prefix.

### How types map

| RBS                        | Accepts                                                           | OpenAPI                                  |
| -------------------------- | ----------------------------------------------------------------- | ---------------------------------------- |
| `String`                   | string                                                            | `string`                                 |
| `Integer`                  | `42`, or `"42"` in a path or query                                | `integer`                                |
| `Float`                    | number                                                            | `number`                                 |
| `bool`                     | `true` / `false`, or `"true"`, `"false"`, `"1"`, `"0"` in a query | `boolean`                                |
| `Date`, `Time`             | ISO 8601 strings                                                  | `string`, format `date` / `date-time`    |
| `T?`                       | absent or `null`                                                  | not required / nullable                  |
| `:low \| :high`            | `"low"` or `"high"`, given to you as a Symbol                     | `enum`                                   |
| `Array[T]`                 | array; repeated keys in a query (`?tag=a&tag=b`)                  | `array`                                  |
| `Hash[String, T]`          | object                                                            | `object` with `additionalProperties`     |
| `{ id: Integer }` (record) | object                                                            | inline `object`                          |
| a class with typed readers | object                                                            | `object` component, referenced by `$ref` |
| `A \| B` (such classes)   | either                                                            | `oneOf`                                  |

A validation failure looks like this:

```json
{
  "type": "about:blank",
  "title": "Unprocessable Content",
  "status": 422,
  "errors": [
    {
      "at": "body.priority",
      "message": "expected :low | :normal | :high, got \"urgent\""
    },
    {
      "at": "body.due_on",
      "message": "expected Date (YYYY-MM-DD), got \"next tuesday\""
    }
  ]
}
```

Mixing typed and untyped is fine. An endpoint without a signature behaves exactly as described in [Inputs](#inputs) and shows up in the docs with untyped parameters.

---

## OpenAPI docs

```ruby
Skyward.app(docs: true) { ... }
```

| Path            | Serves                       |
| --------------- | ---------------------------- |
| `/openapi.json` | the OpenAPI 3.1 document     |
| `/docs`         | an interactive API reference |

Skyward API builds the document from:

- **Routes**, which become paths and operations.
- **Signatures**, which become parameters, request bodies, and one response per member of the return type. A `Skyward::rack` member becomes a `default` response with no schema, because its status and content are known only at runtime.
- **The documentation you write in Ruby**, shown below.
- **Classes with typed readers**, such as `Data` classes or Skyward ORM records, which become reusable components.
- **Providers**, whose failure responses are added to every endpoint that uses them (see below).

### Documenting your API

Documentation is plain Ruby values, written where the thing it describes is declared. Every piece is optional.

```ruby
App = Skyward.app(
  docs: true,
  title: "Best Todos Ever",
  version: "1.0.0",
  description: "Lists of things to do, and the todos on them."
) { ... }

class TodosAPI < Skyward::API
  description "Things to do, and the satisfaction of ticking them off."

  get  "/",             to: :index,    summary: "List todos, newest first."
  post "/:id/complete", to: :complete, summary: "Mark a todo as done.", description: <<~TEXT
    Marking a todo that's already done is fine: it stays done, and the
    response is the same.
  TEXT

  def index(done: nil, limit: 50) = ...
  def complete(id:) = ...
end
```

| Where                          | Says                                    | Becomes                                                            |
| ------------------------------ | --------------------------------------- | ------------------------------------------------------------------ |
| `Skyward.app(title:, version:)` | what the API is                         | the document's `info`, and the heading of `/docs`                  |
| `Skyward.app(description:)`    | more about the API                      | the introduction on `/docs`                                        |
| `description "..."` in a class | what this group of endpoints is for     | its tag's description: a section of `/docs`                        |
| `summary:` on a route          | what the endpoint does, in one line     | the operation's summary                                            |
| `description:` on a route      | anything else a caller needs to know    | the operation's description                                        |

A `summary:` is one line, and Skyward API refuses to boot if it has a line break. A `description:` is Markdown.

Comments are never read. They're for people reading the Ruby, and they never reach your docs, so documentation can't hide in a comment, and a comment can't change what you publish.

Docs are served only when you pass `docs: true`, so leave it out to hide them. The document is built once, at boot. `/docs` renders it with [Scalar](https://github.com/scalar/scalar), loaded from the jsDelivr CDN at a pinned version. The document is your API's contract with the code that calls it. Skyward API doesn't write clients: write the document at build time, and generate a client from it with whatever tooling suits that code:

```sh
$ skyward openapi > openapi.json
```

---

## Building an app

`Skyward.app` is your composition root. It's where real collaborators are created and passed in, and the only place that knows how the pieces fit.

```ruby
# app.rb
require "skyward/api"
require_relative "todos_api"

App = Skyward.app(docs: true) do |app|
  todos = TodoStore.new(database: DB)

  app.use Rack::Deflater
  app.static "/", from: "public"

  app.mount TodosAPI.new(todos:), at: "/todos"
end
```

```ruby
# config.ru
require_relative "app"
run App
```

- `mount` attaches an API object at a prefix.
- `use` is ordinary Rack middleware, and takes the same arguments as `Rack::Builder#use`. It wraps the whole app, in declaration order: the first `use` is outermost, wherever it sits among the other calls.
- `static` serves files from a directory.
- `Skyward.app` returns a frozen Rack app. Nothing about it changes after boot.

Skyward API doesn't build CORS, compression or sessions, because Rack already has them. CORS, for example, is [rack-cors](https://github.com/cyu/rack-cors) through `use`, which answers a preflight `OPTIONS` before it reaches your routes:

```ruby
app.use Rack::Cors do
  allow do
    origins "https://todos.example"
    resource "*", headers: :any, methods: %i[get post delete]
  end
end
```

---

## Providers

Some inputs don't come from the request directly. The current user is one. Register a provider, and any endpoint that asks for that keyword gets its value:

```ruby
class CurrentUser
  # @rbs @sessions: Sessions

  # @rbs sessions: Sessions
  # @rbs return: void
  def initialize(sessions:)
    @sessions = sessions
  end

  # @rbs request: Skyward::Request
  # @rbs return: User | Skyward::Unauthorized
  def call(request)
    @sessions.user_for(request.cookies["session"]) || Skyward.unauthorized("Sign in first")
  end

end

App = Skyward.app do |app|
  app.provide :current_user, CurrentUser.new(sessions: Sessions.new)
  app.mount TodosAPI.new(todos:), at: "/todos"
end
```

```ruby
get "/", to: :index

# @rbs current_user: User
# @rbs return: Array[Todo]
def index(current_user:)
  @todos.for(current_user)
end
```

- A provider is anything that responds to `call(request)`, such as an object, a lambda or a method.
- If a provider returns a response (like `Unauthorized`), the request stops there and your method never runs. Authentication is just a provider.
- Because the provider has a signature, Skyward API knows that every endpoint asking for `current_user:` can respond with a 401, and documents it.
- Provided values never appear as query parameters.

---

## Errors

Skyward API checks your app thoroughly at boot, so mistakes surface when you start it, not at 3am:

```
Skyward::BootError: TodosAPI#show (GET /todos/:id)
  The route has a path parameter :id, but the method has no `id:` keyword.

    get "/:id", to: :show
    ...
    def show(todo_id:)
             ^^^^^^^^
  Did you mean `def show(id:)`?
```

Boot also catches a route that names a method the class doesn't have, a route that shadows another, an unknown type in a signature, and a keyword that matches nothing. With `strict: true`, it also catches an endpoint that has no signature at all.

When your code raises at runtime, Skyward API responds with a 500 problem+json that carries the request ID and logs the exception. In development, the response also includes the backtrace.

```json
{
  "type": "about:blank",
  "title": "Internal Server Error",
  "status": 500,
  "request_id": "5f0c6e1a-7a4e-4a43-9a8e-2f1d3c4b5a69"
}
```

To send exceptions to Sentry or a similar service, pass `on_error:`. It's called once per exception, after it's logged, with the exception and the Rack env, and takes anything that responds to `call(exception, env)`:

```ruby
report = ->(exception, env) { Sentry.capture_exception(exception, tags: { request_id: env["skyward.request_id"] }) }

App = Skyward.app(on_error: report) do |app|
  app.mount TodosAPI.new(todos:), at: "/todos"
end
```

If the hook raises, that's logged too, and the client still gets the original 500. A returned error like `not_found` is a response, not an exception, so it's never reported.

The app is in development when `RACK_ENV`, or `APP_ENV` if `RACK_ENV` isn't set, is `development`, as `skyward serve` sets it. Anything else, including neither being set, is production.

---

## Testing

Endpoints are methods on plain objects, so the fastest test is a method call:

```ruby
describe TodosAPI do
  it "answers 404 for a todo that doesn't exist" do
    api = TodosAPI.new(todos: FakeTodos.new)

    assert_instance_of Skyward::NotFound, api.show(id: 404)
  end
end
```

No server, no Rack, no mocks. You pass the fake in through the front door.

When you want the whole stack, including routing, coercion, providers and middleware, use the test client:

```ruby
describe "POST /todos" do
  let(:client) { Skyward::Test.client(App) }

  it "rejects a priority that doesn't exist" do
    response = client.post "/todos", json: { title: "Ship it", priority: "urgent" }

    assert_equal 422, response.status
    assert_equal "body.priority", response.json[:errors].first[:at]
  end
end
```

`Skyward::Test.client` works with Minitest and RSpec, and with any Rack app.

---

## Production

Here's what you get without configuring anything:

- **Boot does the work. Requests don't.** Routes are compiled into a single matcher, and signatures are compiled into coercers and validators, all at boot. API objects are created once. A request is a route lookup, a coercion and a method call.
- **Bounded request bodies.** A body is read only for an endpoint that takes `body:`, and only up to `Skyward.app(max_body_size:)` bytes, 1 MiB (`1_048_576`) by default. A larger `Content-Length`, or a body that runs past the limit, answers 413 without reading the rest, and a body whose `Content-Type` isn't `application/json` or `*+json` answers 415.
- **Bounded error lists.** A 422 lists at most 1,000 problems, and coercion stops once it has found them, so a small body can't produce a large response.
- **Request IDs.** Skyward API honours an incoming `X-Request-Id`, generates one when it's missing, and returns it on every response.
- **Structured logs.** Every request logs one JSON line with its method, path, status, duration and request ID, to standard output. Pass `Skyward.app(logger: ...)` to send it elsewhere: any object with `info(String)` will do, such as a stdlib `Logger` whose formatter writes the message alone, so each line stays one JSON object. `logger: nil` turns logging off.
- **Safe errors.** In production, a 500 never leaks a backtrace or an exception's message.
- **Strict mode.** Use `Skyward.app(strict: true)` and the app refuses to boot if any endpoint is untyped.
- **YJIT-friendly.** Hot paths are plain method calls with stable object shapes, with no `instance_exec` and no `method_missing`.

Skyward API doesn't manage processes. Run it under Falcon or Puma like any Rack app.

---

## CLI

Skyward API and Skyward ORM share one `skyward` command. Each adds its own commands to it.

| Command           | Does                                                    |
| ----------------- | ------------------------------------------------------- |
| `skyward serve`   | runs the app in development and reloads on file changes |
| `skyward routes`  | prints every route with its handler and signature       |
| `skyward openapi` | writes the OpenAPI document to stdout                   |
| `skyward check`   | boots the app in strict mode, runs Steep, and checks the generated signatures are current |

```
$ skyward routes
GET     /todos              TodosAPI#index     (?done: bool?, ?limit: Integer) -> Array[Todo]
GET     /todos/:id          TodosAPI#show      (id: Integer) -> (Todo | NotFound)
POST    /todos              TodosAPI#create    (body: NewTodo) -> Created[Todo]
POST    /todos/:id/complete TodosAPI#complete  (id: Integer) -> (Todo | NotFound)
DELETE  /todos/:id          TodosAPI#destroy   (id: Integer) -> (NoContent | NotFound)
```

The executable comes with Skyward Core, which every Skyward gem depends on. It finds each gem's `lib/skyward/<gem>/commands.rb` with `Gem.find_files` and loads it, and that file registers the gem's commands:

```ruby
Skyward::Commands.register("routes", "List every route and the method that serves it") do |args|
  # ...
end
```

Skyward API's commands run in your app's directory. `skyward serve` runs `config.ru`, and the others load `app.rb`, which assigns `App = Skyward.app { ... }`.

---

## Coming from…

- **Sinatra.** The routes will feel familiar, but the handler is a named method rather than a block, so you can call it, test it and type it.
- **Rails.** There's no controller instance per request and no `params` hash. Inputs arrive as arguments, and dependencies arrive through `initialize`.
- **FastAPI.** It's the same big idea: the function signature is the API contract. Here it's in Ruby, with RBS instead of type hints.
- **Grape.** You get the docs without the DSL.

---

## Design principles

1. **It's just Ruby.** Classes, methods, keyword arguments and return values. If you can write a method, you can write an endpoint.
2. **Types are a bonus that pays rent.** Nothing requires them. Every signature you add buys coercion, validation, docs and type checking.
3. **One source of truth.** The signature is the contract, so there's no schema written twice.
4. **Responses are values.** You return what happened. Nothing is raised for an ordinary outcome.
5. **Dependencies come in through the front door.** Collaborators arrive through `initialize`, and per-request values through providers. Nothing reaches for globals.
6. **Boot does the work.** Skyward API fails at boot rather than in production, and pays the cost at boot rather than on each request.

---

## Status

This README is the spec. Skyward 0.1 is a skeleton: the gem installs and loads, and only the parts listed here are built. Skyward API is built first, and this section lists each part as it lands.

- **Route declarations.** An API class subclasses `Skyward::API` and lists its routes with `get`, `post`, `put`, `patch` and `delete`, each with an optional `summary:` and `description:`, and describes itself with `description`. A subclass starts with its parent's routes. A path that doesn't start with `/`, a path parameter that isn't a valid keyword name or appears twice, or a `to:` that isn't a Symbol raises `ArgumentError` where it's declared. The rest is checked at boot, below.
- **Building an app.** `Skyward.app` yields a builder and returns a frozen Rack app, and the builder is frozen once the block returns. `mount` attaches an API object at a prefix (`at:`, `/` by default), and raises `Skyward::BootError` given anything but a `Skyward::API` instance. One object can be mounted at several prefixes. A request matches a route when its method and whole path match, trailing slash included, with each path parameter matching one non-empty segment, percent-decoded. Routes are tried in mount order, then declaration order. The method is called with its inputs, below, and its return value is answered by its return type, as Responses below describes. A request whose path no route matches gets a 404 problem+json. `Skyward.app`'s options besides `signatures:`, `logger:`, `on_error:` and `max_body_size:` are still to come.
- **Checks at boot.** `Skyward.app` loads the RBS signatures under `signatures:` (`"sig"` by default, relative to the current directory) along with Skyward API's own, so an app's signatures can subclass `Skyward::API`. It refuses to boot with a `Skyward::BootError` on the first problem it finds, and the message starts with the route's label, such as `TodosAPI#show (GET /todos/:id)`, then says what's wrong and how to fix it. It refuses a `summary:` with a line break; a route that an earlier one with the same verb, in any mount, matches every path of, as `/todos/:id` does `/todos/new`; a method that isn't public, or that takes positional arguments or `**rest`; a class or method with no signature; a signature whose keywords differ from the method's, in name or in being required, which means it's stale; a path parameter with no keyword of its name; a type that can't be read; and a path or query keyword typed as a record, a class, or an array in a path or inside an array. Each endpoint keeps its keywords, with each one's name, its source (the path for a path parameter, the body for `body:`, and otherwise the query string), whether it's required and its type, and keeps the members of its return type, reading `Created[T]` with the type of its value, the other response values by their class, and `Skyward::rack`, or the tuple it names, as a Rack triple, and refusing a `Created` without one. So for now every routed method needs a signature: untyped endpoints and `strict:`, `request:` and provided keywords, source excerpts and "Did you mean" are still to come.
- **Inputs.** Each endpoint's keywords are compiled into coercers at boot, and filled on each request before the method runs: a path parameter from the path, `body:` from the JSON body, and any other keyword from the query string, each coerced to its type. In a path or query, `Integer` matches `-?\d+`, `Float` is parsed with `Float()` and must be finite, and `bool` takes `true`, `false`, `1` and `0`. In a body, a number or boolean must already be one, and an Integer is accepted as a Float. `Date` is `YYYY-MM-DD` and must exist, and `Time` is ISO 8601 with `T`, seconds, an optional fraction and `Z` or `±HH:MM`. A symbol union takes a symbol's name and gives the Symbol, and a union takes its first member that fits, in declared order. `Array[T]` in a query comes from repeated keys, one value is a one-item array, and `tag[]` is a different key; any other keyword given more than once doesn't fit. A record becomes a Hash with Symbol keys, and a class with typed readers is built with `new(**fields)`, both ignoring undeclared keys. An empty query value is a value, so `?limit=` doesn't fit `Integer`. A missing required keyword or field is `nil` when it's nullable, and otherwise `is required`. An absent optional keyword isn't passed, so Ruby's default applies, and an absent optional record field is left out. A request that doesn't fit answers a 422 problem+json titled `Unprocessable Content`, whose `errors` list every problem, up to the first 1,000, after which coercion stops, each with where it is (`path.id`, `query.limit`, `body.priority`, `body.tags[1]`) and a message, such as `expected :low | :normal | :high, got "urgent"`. A query string with unescaped bytes outside ASCII is a 422 at `query`, and a body that isn't JSON, or isn't UTF-8, is a 422 at `body`. The body is read only for an endpoint with `body:`, as [Production](#production) describes, and a missing or empty one is absent. `Hash[String, T]`, untyped endpoints, `request:` and providers are still to come.
- **Responses.** An API's instances have private helpers that return frozen response values, each taking `headers:`: `created(value)` returns a `Skyward::Created[T]`, `no_content` a `Skyward::NoContent`, `bad_request(detail)` a `Skyward::BadRequest`, `unauthorized(detail)` a `Skyward::Unauthorized`, `forbidden(detail)` a `Skyward::Forbidden`, `not_found(detail = nil)` a `Skyward::NotFound`, `conflict(detail)` a `Skyward::Conflict`, `unprocessable(detail)` a `Skyward::Unprocessable` and `redirect(to, status: 303)` a `Skyward::Redirect`. `bad_request`, `unauthorized`, `forbidden` and `redirect` are also public module functions on `Skyward`, such as `Skyward.unauthorized("Sign in first")`, for code outside an API class. `redirect` raises `ArgumentError` for a `status:` other than 301, 302, 303, 307 or 308, or a `to` with a line break. At boot, each endpoint compiles a serializer for every member of its return type, and a returned value goes to the first member it fits: by class for a class with typed readers and for a response value, and by shape otherwise. A class with typed readers is written by calling each reader it declares, never `to_h`, and a record is read from a Hash by its declared keys, leaving out an optional key that's absent, so nothing undeclared is ever written. Integers, Floats, Strings and booleans are written as JSON, an enum's Symbol as its name, a `Date` as `YYYY-MM-DD`, a `Time` in UTC as ISO 8601 with six fractional digits (`2026-10-18T09:30:00.123456Z`), and `nil` only where the type is nullable. A plain value answers 200 with `content-type: application/json`; `Created[T]` answers 201 with its value written as `T`; `NoContent` answers 204 with no body; `BadRequest`, `Unauthorized`, `Forbidden`, `NotFound`, `Conflict` and `Unprocessable` answer 400, 401, 403, 404, 409 and 422 with RFC 9457 `application/problem+json`, whose `detail` appears only when given; and `Redirect` answers its status with a `location` header and no body. A response value's `headers:` are added to its response, and Skyward adds no `WWW-Authenticate` to a 401, so pass it in `headers:`. A part typed `untyped` is written as untyped code's is: scalars as themselves, Symbols as their names, dates and times as above, Hashes and Arrays item by item, and anything else through `to_h`; a return type of `untyped` also answers each response value with its own status. A value, or any part of it, that doesn't fit its type raises `Skyward::API::ReturnTypeError` before anything is written, naming the endpoint's label, what came back (a scalar's value, or else only its class) and where, and the type it should have been, so it's answered with a 500 as Errors below describes. Skyward API's signatures declare `Skyward::rack` as `[Integer, Hash[String, String], untyped]`, and a member typed with it, or with that tuple written out, takes an Array of an Integer, a Hash and a body, and sends it as given, without checking or rewriting any of it, so a body that streams through `each` or `call` works. An `Array[T]` member is always JSON, even for three items. The request ID is still added to a triple, and `HEAD` drops its body, closing it when it responds to `close`. `Hash[String, T]`, untyped endpoints and their triples are still to come.
- **Request IDs.** The app `Skyward.app` returns gives every request an ID: an incoming `X-Request-Id` of 1 to 200 visible ASCII characters with no spaces, or else a random UUID from `SecureRandom`. The ID is stored in the Rack env as `skyward.request_id` before anything else runs, and every response carries it as `x-request-id`, replacing one the app set.
- **HTTP's own answers.** A path that matches routes only under other methods gets a 405 problem+json with an `allow` header listing the methods of every route matching it, in the order `GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS`, with `HEAD` wherever there's `GET` and always `OPTIONS`. `HEAD` runs the GET route and answers its status and headers with an empty body. `OPTIONS` on a routed path answers 204 with `allow`, and on any other path 404. CORS is still to come.
- **`skyward serve`.** Skyward API registers it with the `skyward` command. It runs the current directory's `config.ru`, needing no `app.rb`, under one Falcon process bound to `localhost`, on `PORT` (9292 by default), with `RACK_ENV=development` unless it's already set. It writes no files. With no `config.ru`, or no Falcon in the bundle `skyward` runs in, it exits 1 saying what to do. Under `bundle exec` that's the app's bundle; run bare, `skyward` sees every installed gem. It reloads the app when a `.rb`, `.rbs` or `config.ru` file under the directory is added, changed or removed, outside `tmp/`, `log/`, `vendor/`, `node_modules/` and hidden directories such as `.git/` and `.bundle/`, polling modification times at most once every half second. The first request after a change clears the routes and description of every API class defined in those files, drops those files from `$LOADED_FEATURES` so their `require`s run again, unloads and unregisters each Zeitwerk loader that manages only directories there (so `config.ru` can set it up again), reloads any other Zeitwerk loader with reloading enabled, and builds a new app from `config.ru`. A loader of the app's own needs reloading enabled: Zeitwerk can't unload one without it, or enable it after setup, so the reload fails saying to call `loader.enable_reloading` in development and restart. One reload runs at a time and requests wait for it, while a request in flight finishes on the app it started with. A load that raises, at boot or on a reload, including a `Skyward::BootError` or a `SyntaxError`, answers every request until the next change retries it with the development 500 described under Errors: `type`, `title`, `status`, `detail` and `backtrace`, and an empty body for `HEAD`. It has no `request_id`, because the app that assigns request IDs is the one that failed to load, and nothing is logged. Only `skyward serve` reloads. The other commands are still to come.
- **The test client.** `Skyward::Test.client(app)` drives any object with `call(env)` in-process, with no server, and never loads Minitest or RSpec. Its `get`, `post`, `put`, `patch`, `delete`, `head` and `options` each take a path, which may include a query string. `json:` sends a JSON body with `content-type: application/json`, and without it no body is sent. `headers:` sends request headers by their HTTP names, and `cookies:` sends a Hash as a `cookie` header. Each returns a frozen response with `status`, `headers` as the app returned them, `body` as text, and `json`, the body parsed with Symbol keys when the content type is JSON or `+json` and the body isn't empty, and `nil` otherwise. The client reads the whole body and closes it when it responds to `close`.
- **Middleware.** `use` adds Rack middleware, with the same arguments as `Rack::Builder#use`, so CORS comes from rack-cors. Middleware wraps the routes in declaration order, the first `use` outermost, wherever it sits relative to `mount`. Request IDs and request logs sit outside it, so a response from middleware still carries an ID and is logged. The stack is built once, at boot, and the app stays frozen, though the middleware objects themselves aren't frozen. Error handling sits outside it too, so an exception from middleware is still answered with a 500.
- **Request logs.** Unless `Skyward.app` is given `logger: nil`, every request logs one JSON object on one line, whatever answered it, including a 404 or a 500: `time` (when the request arrived, ISO 8601 in UTC to the millisecond), `method`, `path` (Rack's `SCRIPT_NAME` and `PATH_INFO`, so never the query string), `status`, `duration_ms` (until the app returns its response, to two decimal places) and `request_id`. It writes to `$stdout`, or calls `info` on the `logger:` it's given.
- **Errors.** A `StandardError` raised inside the app, from an endpoint, serializing its return value, or middleware, is caught just inside the request log, so the request still logs with status 500 and the ID. Other exceptions, like `Interrupt`, aren't caught. The response is a 500 `application/problem+json` with `type`, `title`, `status` and `request_id`, and an empty body for `HEAD`. The exception is logged first, as one JSON line through the `logger:` with `level` (`"error"`), `request_id`, `class`, `message` and `backtrace`, unless `logger: nil`. Then it's handed to `Skyward.app(on_error:)`, anything with `call(exception, env)`; if that raises, its exception is logged the same way and the client still gets the original 500. In development, when `RACK_ENV`, or else `APP_ENV`, is `development`, the body adds `detail` (the exception's class and message) and `backtrace` (an array of lines). Under `skyward serve`, an app that fails to load or reload answers this development 500 too, without a `request_id`, as the `skyward serve` bullet above says.
- **Static files.** `static` serves a directory's files under a URL prefix, for GET and HEAD, inside the middleware. Its `from:` is resolved against the current directory at boot, and a directory that doesn't exist raises `Skyward::BootError`. A matching route takes precedence over a file, and several `static` calls are tried in order until one has the file. A path routed only under other methods still serves its file to GET and HEAD, and answers the rest with the 405. The prefix itself, or any path ending in `/`, serves that directory's `index.html`. A missing file, a directory without a trailing slash, or a path with a `..` segment, escaped or not, is answered as if there were no `static`: a 404, or a 405 on a path routed under other methods. A file carries a `content-type` from its extension (`application/octet-stream` when unknown), its `content-length`, `last-modified`, an `etag` built from its modification time in nanoseconds and its size, and `cache-control: no-cache`, and `HEAD` answers them with no body. A matching `If-None-Match`, or an `If-Modified-Since` no earlier than the modification time, answers 304 with no body.
