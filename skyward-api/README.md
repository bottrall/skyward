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
- **Signatures**, which become parameters, request bodies, and one response per member of the return type.
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
- `use` is ordinary Rack middleware.
- `static` serves files from a directory.
- `Skyward.app` returns a frozen Rack app. Nothing about it changes after boot.

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
- **Request IDs.** Skyward API honours an incoming `X-Request-Id`, generates one when it's missing, and returns it on every response.
- **Structured logs.** Every request logs one JSON line with its method, path, status, duration and request ID. Pass your own with `Skyward.app(logger: ...)`.
- **Safe errors.** In production, a 500 never leaks a backtrace.
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

- **Route declarations.** An API class subclasses `Skyward::API` and lists its routes with `get`, `post`, `put`, `patch` and `delete`, each with an optional `summary:` and `description:`, and describes itself with `description`. A subclass starts with its parent's routes. A path that doesn't start with `/`, a path parameter that isn't a valid keyword name or appears twice, or a `to:` that isn't a Symbol raises `ArgumentError` where it's declared. The checks at boot are still to come.
- **Building an app.** `Skyward.app` yields a builder and returns a frozen Rack app, and the builder is frozen once the block returns. `mount` attaches an API object at a prefix (`at:`, `/` by default), and raises `Skyward::BootError` given anything but a `Skyward::API` instance. One object can be mounted at several prefixes. A request matches a route when its method and whole path match, trailing slash included, with each path parameter matching one non-empty segment, percent-decoded. Routes are tried in mount order, then declaration order. The method is called with its path parameters as `String` keywords, and its return value is answered as JSON with status 200. A request no route matches gets a 404 problem+json, and an exception from the method a 500 that doesn't reveal it. Other inputs, types, the response helpers, and `Skyward.app`'s other options are still to come.
- **Request IDs.** The app `Skyward.app` returns gives every request an ID: an incoming `X-Request-Id` of 1 to 200 visible ASCII characters with no spaces, or else a random UUID from `SecureRandom`. The ID is stored in the Rack env as `skyward.request_id` before anything else runs, and every response carries it as `x-request-id`, replacing one the app set. Logging it and putting it in a 500's body are still to come.
- **`skyward serve`.** Skyward API registers it with the `skyward` command. It runs the current directory's `config.ru`, needing no `app.rb`, under one Falcon process bound to `localhost`, on `PORT` (9292 by default), with `RACK_ENV=development` unless it's already set. It writes no files. With no `config.ru`, or no Falcon in the bundle `skyward` runs in, it exits 1 saying what to do. Under `bundle exec` that's the app's bundle; run bare, `skyward` sees every installed gem. Reloading on file changes, and the other commands, are still to come.
