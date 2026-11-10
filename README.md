# Skyward

> [!CAUTION]
> **Work in progress: Skyward works, but it isn't finished.** Skyward API serves typed endpoints and publishes their OpenAPI document, Skyward ORM reads and writes SQLite and PostgreSQL and generates its own migrations, and `skyward new` writes an app that uses both. Each gem's README is its spec, though, and a few parts of the API and ORM specs aren't built yet: each README's Status section lists what is. Until 1.0, any release may change the API, so don't depend on Skyward in production yet.

Typed Ruby web apps, in four gems. An endpoint is a method, a row is a value, and RBS signatures are the contract between them, your type checker and your API's consumers.

```ruby
# @rbs use Skyward::API::*

class TodosAPI < Skyward::API
  get "/todos/:id", to: :show

  # @rbs id: Integer
  # @rbs return: Todo | Responses::NotFound
  def show(id:)
    Todo.find_by(id:) || not_found
  end
end
```

Skyward API coerces and validates `id` from the signature, publishes the endpoint in an OpenAPI 3.1 document, and Steep checks the method. Skyward ORM returns `Todo` rows as frozen values, and writes the migrations from the class.

## The gems

| Gem | What it is |
| --- | --- |
| [`skyward-api`](skyward-api/README.md) | A small, fast web framework where an endpoint is a method, typed with RBS. Its published output is an OpenAPI 3.1 document, from which consumers generate their own clients. |
| [`skyward-orm`](skyward-orm/README.md) | A small, fast ORM where a class is a table and its rows are values, on PostgreSQL or SQLite. |
| [`skyward`](skyward/README.md) | Both of the above, and `skyward new`. |
| [`skyward-core`](skyward-core/README.md) | The plumbing the others share. You never add it yourself. |

Skyward API and Skyward ORM each work without the other. All four gems release together, at one version.

## Getting started

[The getting-started guide](docs/getting-started.md) takes you from `gem install skyward` to a running, tested, documented API. For agents, [`llms.txt`](llms.txt) lists Skyward's docs as Markdown.

## Ruby

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026), and CI tests each one.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports go through [`SECURITY.md`](SECURITY.md).

## License

[MIT](LICENSE).
