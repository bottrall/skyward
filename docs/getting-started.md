# Getting started with Skyward

This guide takes you from installing Skyward to a running, tested, documented API. It's written for Skyward 0.3. You start from the blank app `skyward new` writes and build a resource in it, todos, from nothing. Each step shows the command to run, the code to write and the output to expect. Where output is long, `...` marks what's left out. Timestamps, migration versions, request IDs and test seeds will differ on your machine.

## 1. Install Skyward

You need Ruby 3.3 or later.

```sh
$ gem install skyward
...
Successfully installed skyward-0.3.0
```

That gives you the `skyward` command. Run it on its own to see what it can do:

```sh
$ skyward
Usage: skyward COMMAND [ARGS]
  check      Check signatures, boot app.rb in strict mode and run Steep
  migrate    Run the pending migrations in db/migrate
  migration  Write the migration that brings the database in line with your table classes
  new        Write a new app in NAME/ and install its gems, unless given --skip-bundle
  openapi    Write the OpenAPI document to stdout
  rollback   Undo the latest migration by running its -- down section
  routes     Print every route with its handler and signature
  serve      Serve config.ru with Falcon in development, on PORT (default 9292)
  status     List which migrations have run, and how your table classes differ from the database
```

## 2. Create an app

```sh
$ skyward new todos
Wrote todos/.gitignore
Wrote todos/AGENTS.md
Wrote todos/Gemfile
Wrote todos/Rakefile
Wrote todos/Steepfile
Wrote todos/app.rb
Wrote todos/bin/ci
Wrote todos/bin/setup
Wrote todos/bin/test
Wrote todos/boot.rb
Wrote todos/config.ru
Wrote todos/db/migrate/.keep
Wrote todos/lib/health_api.rb
Wrote todos/modules/.keep
Wrote todos/rbs_collection.yaml
Wrote todos/sig/generated/app.rbs
Wrote todos/sig/generated/boot.rbs
Wrote todos/sig/generated/health_api.rbs
Wrote todos/test/app_test.rb
Wrote todos/test/lib/health_api_test.rb
Wrote todos/test/test_helper.rb
...
Bundle complete! 7 Gemfile dependencies, 62 gems now installed.
Use `bundle info [gemname]` to see where a bundled gem is installed.
Next: cd todos && bin/setup
```

`bin/setup` installs the gems, downloads the signatures that Steep, the type checker, needs for them, and creates the development database at `db/todos.sqlite3`. There are no migrations yet:

```sh
$ cd todos
$ bin/setup
...
Bundle complete! 7 Gemfile dependencies, 62 gems now installed.
...
It's done! 20 gems' RBSs now installed.
No pending migrations.
```

From here on, every command runs in the `todos` directory.

## 3. A tour of the app

The app is an API with no frontend, and it starts blank. The files that matter most:

- `app.rb` builds the app and wires each API to what it needs. It's the one place that does.
- `lib/health_api.rb` is `HealthAPI`, the app's one endpoint so far: `GET /up`, for load balancers and uptime checks.
- `modules/` is empty. It's where your code goes, one directory per resource.
- `db/migrate/` is empty too. It's where the migrations go, as plain SQL.
- `boot.rb` loads `lib/` and `modules/`, and connects to the database: `DATABASE_URL` if it's set, and otherwise SQLite at `db/todos.sqlite3`.
- `sig/generated/` holds the type signatures, generated from the `#:` and `# @rbs` comments in the Ruby. `skyward serve`, `skyward migration` and the other commands that read types regenerate it first, so you never edit or regenerate it by hand.
- `test/` holds the tests, and `bin/test` and `bin/ci` run them.
- `AGENTS.md` teaches a coding agent working in the app its conventions. It's a good read for people too.

The app mounts `HealthAPI` and turns on the API reference at `/docs`:

```ruby
# app.rb
# frozen_string_literal: true

# rbs_inline: enabled

require_relative 'boot'

App = Skyward.app(docs: true, title: 'Todos') do |app|
  app.mount HealthAPI.new
end #: Skyward::API::_RackApp
```

An endpoint is a public method. Its route goes at the top of the class, and its `# @rbs return:` line is its contract:

```ruby
# lib/health_api.rb
# frozen_string_literal: true

# rbs_inline: enabled

class HealthAPI < Skyward::API
  description 'Whether the app is up, for load balancers and uptime checks.'

  get '/up', to: :show, summary: 'Report that the app is up.'

  # @rbs return: { status: "ok" }
  def show = { status: 'ok' }
end
```

[Starting an app](../skyward/README.md#starting-an-app) lists every file.

## 4. Add a table class

A todo is a title and whether it's done. Its code goes in `modules/todos/`, and file paths match constant names, so the table class is `Todos::Record`. First declare the `Todos` module, in a file of its own, so it has a signature too:

```ruby
# modules/todos.rb
# frozen_string_literal: true

# rbs_inline: enabled

module Todos
end
```

Then the table class. Each typed `attr_reader` is a column, and each row comes back as a frozen instance of the class:

```ruby
# modules/todos/record.rb
# frozen_string_literal: true

# rbs_inline: enabled

class Todos::Record < Skyward::ORM::Record
  table :todos
  default done: false
  check :title, length: 1..200

  # @dynamic id, title, done
  attr_reader :id     #: Integer
  attr_reader :title  #: String
  attr_reader :done   #: bool
end
```

The class body is the schema: the rows live in `todos`, a new todo isn't done, and a title is 1 to 200 characters. The `# @dynamic` line lists the columns for Steep, which doesn't count an `attr_reader` as defining a method.

## 5. Migrate the database

Skyward writes the migration for you, by comparing the table class with the database. It reads the column types from `sig/generated`, which it regenerates from the Ruby first, so it sees `Todos::Record`:

```sh
$ bundle exec skyward migration create_todos
Todos::Record has no table yet:
  + todos  3 columns, 1 check
Wrote db/migrate/20261110050204_create_todos.sql. Review it, then run `skyward migrate`.
```

Review the SQL before you run it. It's yours to edit and commit:

```sql
-- db/migrate/20261110050204_create_todos.sql
CREATE TABLE todos (
  id     INTEGER CONSTRAINT todos_pkey PRIMARY KEY,
  title  TEXT    NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200),
  done   INTEGER NOT NULL DEFAULT 0
);

-- down
DROP TABLE todos;
```

The SQL is written for the database the app connects to, here SQLite, which stores a `bool` as an `INTEGER` that's 0 or 1. The `-- down` section is what `skyward rollback` runs.

Then run it:

```sh
$ bundle exec skyward migrate
Migrated 20261110050204
```

## 6. Add a typed API

The endpoints go in `Todos::API`. Its routes go at the top of the class, and each names the method it calls:

```ruby
# modules/todos/api.rb
# frozen_string_literal: true

# rbs_inline: enabled

# @rbs use Skyward::API::*

class Todos::API < Skyward::API
  description 'Things to do, and the satisfaction of ticking them off.'

  get  '/',             to: :index,    summary: 'List todos, newest first.'
  get  '/:id',          to: :show,     summary: 'Fetch a single todo.'
  post '/',             to: :create,   summary: 'Create a todo.'
  post '/:id/complete', to: :complete, summary: 'Mark a todo as done.'

  NewTodo = Data.define(
    :title #: String
  )

  # @rbs @todos: singleton(Todos::Record)

  # @rbs todos: singleton(Todos::Record)
  # @rbs return: void
  def initialize(todos:)
    super()
    @todos = todos
  end

  # @rbs limit: Integer
  # @rbs return: Array[Todos::Record]
  def index(limit: 50)
    @todos.order(id: :desc).limit(limit).to_a
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record | Responses::NotFound
  def show(id:)
    @todos.find_by(id:) || not_found
  end

  # @rbs body: NewTodo
  # @rbs return: Responses::Created[Todos::Record] | Responses::Unprocessable
  def create(body:)
    todo = @todos.into(Todos::Record).insert(title: body.title)
    case todo
    when Todos::Record then created todo
    else unprocessable 'A title needs 1 to 200 characters'
    end
  end

  # @rbs id: Integer
  # @rbs return: Todos::Record | Responses::NotFound
  def complete(id:)
    @todos.where(id:).into(Todos::Record).update!(done: true).first || not_found
  end
end
```

An endpoint's keywords are its inputs, and the `# @rbs` lines are its contract. `id: Integer` makes Skyward turn the `"1"` in `/todos/1` into `1`, and answer 422 for `/todos/abc` before the method runs. `limit: 50` has a default, so it's an optional query parameter, and `body: NewTodo` is the JSON request body, checked against `NewTodo` before `create` runs. The return types say which responses each endpoint can answer with, and they go into the API's documentation.

A write returns how many rows it changed, unless `into` names the rows to return. So `into(Todos::Record)` makes `insert` return the new todo, or a `Skyward::ORM::Violation` when the database refuses it, as it does an empty title. That's an outcome, not an exception, so `create` matches it with `case`/`when` and answers 201 or 422. In `complete`, `update!` returns the todos it changed, and there's none when no todo has the `id`, so the endpoint answers 404. It's the bang version because setting `done` can't break a rule, so a violation there would be a bug, and it raises.

`Todos::API` takes the table class it queries as `todos:`, rather than reaching for `Todos::Record` itself, so a test can pass in whatever it likes.

## 7. Mount it

Mount the API in `app.rb`, at `/todos`, and pass it the table class:

```ruby
# app.rb
# frozen_string_literal: true

# rbs_inline: enabled

require_relative 'boot'

App = Skyward.app(docs: true, title: 'Todos') do |app|
  app.mount HealthAPI.new
  app.mount Todos::API.new(todos: Todos::Record), at: '/todos'
end #: Skyward::API::_RackApp
```

List the routes to see each with its signature, which `skyward routes` regenerates from the comments first:

```sh
$ bundle exec skyward routes
GET   /up                  HealthAPI#show       () -> { status: "ok" }
GET   /todos               Todos::API#index     (?limit: Integer) -> Array[Todos::Record]
GET   /todos/:id           Todos::API#show      (id: Integer) -> (Todos::Record | Responses::NotFound)
POST  /todos               Todos::API#create    (body: NewTodo) -> (Responses::Created[Todos::Record] | Responses::Unprocessable)
POST  /todos/:id/complete  Todos::API#complete  (id: Integer) -> (Todos::Record | Responses::NotFound)
```

## 8. Test it

An endpoint is a method on a plain object, so its test calls it. The tests mirror the code, so `Todos::API`'s go in `test/modules/todos/api_test.rb`:

```ruby
# test/modules/todos/api_test.rb
# frozen_string_literal: true

require 'test_helper'

describe Todos::API do
  let(:api) { Todos::API.new(todos: Todos::Record) }

  def create(title = 'Ship it') = Todos::Record.into(Todos::Record).insert!(title:)

  describe '#index' do
    it 'lists the newest todo first' do
      %w[First Second].each { |title| create(title) }

      assert_equal %w[Second First], api.index.map(&:title)
    end

    it 'lists at most limit todos' do
      %w[First Second].each { |title| create(title) }

      assert_equal %w[Second], api.index(limit: 1).map(&:title)
    end
  end

  describe '#show' do
    it 'answers the todo' do
      todo = create

      assert_equal todo, api.show(id: todo.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.show(id: 0)
    end
  end

  describe '#create' do
    it 'answers the new todo, created' do
      todo = api.create(body: Todos::API::NewTodo.new(title: 'Ship it')).value

      assert_equal Todos::Record.find_by(id: todo.id), todo
    end

    it "answers 422 for a title that's empty" do
      response = api.create(body: Todos::API::NewTodo.new(title: ''))

      assert_instance_of Skyward::API::Responses::Unprocessable, response
    end
  end

  describe '#complete' do
    it 'answers the todo, done' do
      todo = create

      assert_equal todo.with(done: true), api.complete(id: todo.id)
    end

    it "answers 404 for a todo that doesn't exist" do
      assert_instance_of Skyward::API::Responses::NotFound, api.complete(id: 0)
    end
  end
end
```

Rows are values, so the tests compare them with `==`, and `todo.with(done: true)` is the same todo, done. Skyward checks each request against the method's signature before the method runs, as it does the `abc` in `/todos/abc`, so the tests don't repeat that.

`test/app_test.rb` tests what `app.rb` decides, over HTTP, with `Skyward::API::Test.client`, which calls the app in-process without a server: one request to each API at the path it's mounted at, and that `/openapi.json` documents every path and `/docs` is served. Endpoint behaviour stays in the API's own test. Add a test that `Todos::API` is mounted at `/todos`, inside `describe "App"`, after the test of `/up` that came with the app:

```ruby
describe 'GET /todos' do
  it 'serves Todos::API' do
    response = client.get('/todos')

    assert_equal [200, []], [response.status, response.json]
  end
end
```

Then add `Todos::API`'s paths to the list the `/openapi.json` test expects:

```ruby
assert_equal %i[/up /todos /todos/{id} /todos/{id}/complete], paths
```

Each test runs in a transaction that's rolled back after it, on a database of its own, so every test starts with no todos, and the tests never see your development data. Run them:

```sh
$ bin/test
Run options: --seed 23760

# Running:

.............

Finished in 0.004612s, 2818.9128 runs/s, 3035.7523 assertions/s.

13 runs, 14 assertions, 0 failures, 0 errors, 0 skips
```

## 9. Run CI

`bin/ci` runs everything CI should: it regenerates the signatures and fails if that changed them, runs the tests, then runs `skyward check`, which checks the signatures again, boots the app in strict mode, so an endpoint without types fails it, and type-checks the code with Steep. Run it before you push:

```sh
$ bin/ci
...
🎉 Generated 6 RBS files under sig/generated
Run options: --seed 53426

# Running:

.............

Finished in 0.004623s, 2811.7671 runs/s, 3028.0569 assertions/s.

13 runs, 14 assertions, 0 failures, 0 errors, 0 skips
Migrated 20261110050204
Signatures: passed
Strict boot: passed
Steep: passed
# Type checking files:

............

No type error detected. 🧉
```

The `Migrated` line is for a database `bin/ci` makes for `skyward check` and deletes after, not your development database.

## 10. Run it

```sh
$ bundle exec skyward serve
{"time":"...","severity":"info",...,"message":"Falcon v0.57.0 taking flight! ...\n- Binding to: #<Falcon::Endpoint http://localhost:9292/ {}>\n..."}
...
```

It serves the app on port 9292, or on `PORT` if you set it, and reloads it whenever you change a file, regenerating `sig/generated` first when you change Ruby. Every request logs one line of JSON. In another terminal, check it's up, then create a todo:

```sh
$ curl localhost:9292/up
{"status":"ok"}
$ curl -i -X POST localhost:9292/todos -H "content-type: application/json" -d '{"title":"Buy milk"}'
HTTP/1.1 201 Created
content-type: application/json
x-request-id: 2e444adb-8ca9-4ee3-9c3c-494e26e51c05
vary: accept-encoding
content-length: 40

{"id":1,"title":"Buy milk","done":false}
```

List the todos, mark it as done, and fetch it:

```sh
$ curl localhost:9292/todos
[{"id":1,"title":"Buy milk","done":false}]
$ curl -X POST localhost:9292/todos/1/complete
{"id":1,"title":"Buy milk","done":true}
$ curl localhost:9292/todos/1
{"id":1,"title":"Buy milk","done":true}
```

The types do their work on requests that don't fit. A todo that doesn't exist is a 404, an `id` that isn't a number is refused before the method runs, and the database refuses an empty title:

```sh
$ curl -X POST localhost:9292/todos/42/complete
{"type":"about:blank","title":"Not Found","status":404}
$ curl -X POST localhost:9292/todos/abc/complete
{"type":"about:blank","title":"Unprocessable Content","status":422,"errors":[{"at":"path.id","message":"expected Integer, got \"abc\""}]}
$ curl -X POST localhost:9292/todos -H "content-type: application/json" -d '{"title":""}'
{"type":"about:blank","title":"Unprocessable Content","status":422,"detail":"A title needs 1 to 200 characters"}
```

Now open <http://localhost:9292/docs> in your browser. It's the API reference, built from the routes, their summaries and their signatures. The page itself is small, and loads [Scalar](https://github.com/scalar/scalar) to render the OpenAPI document at `/openapi.json`:

```sh
$ curl localhost:9292/docs
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Todos</title>
  </head>
  ...
</html>
```

Stop the server with Ctrl-C.

## 11. Hand the API to its consumers

The OpenAPI document is your API's contract with the code that calls it. Write it to a file:

```sh
$ bundle exec skyward openapi > openapi.json
$ head -6 openapi.json
{
  "openapi": "3.1.0",
  "info": {
    "title": "Todos",
    "version": "0.1.0"
  },
```

It's the same document the app serves at `/openapi.json`, and the same app always writes the same bytes, so you can commit it and see in review how a change alters the contract.

Skyward doesn't write clients. Each consumer generates its own from the document, with whatever tooling suits its code. For example, a TypeScript frontend could use [OpenAPI Generator](https://openapi-generator.tech), which isn't part of Skyward:

```sh
$ docker run --rm -v "$PWD:/local" openapitools/openapi-generator-cli generate -i /local/openapi.json -g typescript-fetch -o /local/client
```

## Next

- [Skyward API](../skyward-api/README.md) covers endpoints, inputs, responses, providers, errors and the OpenAPI document in full.
- [Skyward ORM](../skyward-orm/README.md) covers tables, queries, writes, transactions and migrations.
- [`examples/todos`](../examples/todos/README.md) is a larger version of this app on SQLite, the database `skyward new` sets up, with lists, priorities, due dates and a service between the API and the table, and [`examples/todos_postgres`](../examples/todos_postgres/README.md) is the same app on PostgreSQL, each with the migration `skyward migration` wrote on its database.
