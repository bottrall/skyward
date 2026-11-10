# Skyward

Typed JSON APIs in Ruby. You write the RBS types, and Skyward validates requests against them, publishes them as OpenAPI and writes your database migrations from them.

> [!CAUTION]
> Skyward is pre-1.0. It works, but parts of each gem's spec aren't built yet, and any release may change the API. Don't run it in production yet.

## What it looks like

A table is a class with typed readers:

```ruby
# rbs_inline: enabled

class Todo < Skyward::ORM::Record
  table :todos
  default priority: :normal, done: false

  # @dynamic id, title, priority, done
  attr_reader :id        #: Integer
  attr_reader :title     #: String
  attr_reader :priority  #: :low | :normal | :high
  attr_reader :done      #: bool
end
```

You don't write its migration. Skyward compares the class with the database and writes the SQL:

```
$ skyward migration create_todos
Todo has no table yet:
  + todos  4 columns, 1 check
Wrote db/migrate/20261110030311_create_todos.sql. Review it, then run `skyward migrate`.
```

An endpoint is a method. Its inputs are keyword arguments, its response is the return value, and its signature is the API contract:

```ruby
# rbs_inline: enabled
# @rbs use Skyward::API::*

NewTodo = Data.define(
  :title,    #: String
  :priority  #: :low | :normal | :high
)

class TodosAPI < Skyward::API
  get  "/todos/:id", to: :show
  post "/todos",     to: :create

  # @rbs id: Integer
  # @rbs return: Todo | Responses::NotFound
  def show(id:)
    Todo.find_by(id:) || not_found
  end

  # @rbs body: NewTodo
  # @rbs return: Responses::Created[Todo]
  def create(body:)
    created Todo.into(Todo).insert!(**body.to_h)
  end
end
```

A request that doesn't match the signature never reaches your method:

```
$ curl --json '{"title": "Ship it", "priority": "urgent"}' localhost:9292/todos
{"type":"about:blank","title":"Unprocessable Content","status":422,"errors":[{"at":"body.priority","message":"expected :low | :normal | :high, got \"urgent\""}]}
```

The same signatures are your OpenAPI 3.1 document at `/openapi.json`, with an API reference at `/docs`, and Steep type-checks your methods against them. A `Todo` read from the database and a `Todo` sent as JSON are the same type, and the app won't boot if the database doesn't match the class.

If you've used FastAPI, the API half is the same idea. If you've used ActiveRecord, the ORM half does less on purpose: rows are frozen values, and there are no callbacks, no lazy loading and no associations, so every query is one you wrote.

## Try it

```sh
$ gem install skyward
$ skyward new todos
$ cd todos && bin/setup
$ bundle exec skyward serve   # http://localhost:9292/docs
```

`skyward new` writes a working app with typing, tests and CI set up. [The getting-started guide](docs/getting-started.md) goes from there to a new column, a new endpoint and their tests. If you're an agent, start at [`llms.txt`](llms.txt).

## The gems

| Gem | What it is |
| --- | --- |
| [`skyward-api`](skyward-api/README.md) | The web framework: endpoints are methods, and their RBS signatures validate requests and become the OpenAPI document. |
| [`skyward-orm`](skyward-orm/README.md) | The ORM, for PostgreSQL and SQLite: a class is a table, its rows are frozen values, and migrations are written from the class. |
| [`skyward`](skyward/README.md) | Both, plus `skyward new`. |
| [`skyward-core`](skyward-core/README.md) | What the others share. You never add it yourself. |

Each README is that gem's spec, and its Status section lists what's built. The API and the ORM each work without the other, and all four gems release together at one version.

## Ruby

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026), and CI tests each one.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports go through [`SECURITY.md`](SECURITY.md).

## License

[MIT](LICENSE).
