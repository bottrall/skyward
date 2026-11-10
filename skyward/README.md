# Skyward

> [!CAUTION]
> Skyward is pre-1.0. Everything this README describes is built, as [Status](#status) lists, but parts of the [Skyward API](../skyward-api/README.md#status) and [Skyward ORM](../skyward-orm/README.md#status) specs aren't yet. Any release may change the API, so don't run it in production yet.

This gem installs both halves of Skyward, and adds `skyward new`, which writes an app that uses them:

- [Skyward API](../skyward-api/README.md), a web framework where an endpoint is a method and its RBS signature is the API contract.
- [Skyward ORM](../skyward-orm/README.md), an ORM where a class is a table, its rows are frozen values and its migrations are written for you.

Each works without the other. Add this gem when you want both.

## Install

```ruby
# Gemfile
gem "skyward"
```

```ruby
require "skyward" # requires skyward/api and skyward/orm
```

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026).

## Starting an app

```sh
$ skyward new todos
```

`skyward new` writes a working app: `app.rb` and `boot.rb`, a `Steepfile` with typing set up, tests, `bin/ci`, and an `AGENTS.md` that teaches an agent working in the app its conventions. Then it runs `bundle install` in the app, unless you pass `--skip-bundle`.

The name is lowercase letters, digits and underscores, starting with a letter, so it names the app's directory and, camelized, its title (`my_app` is `MyApp`). `skyward new` refuses a directory that already has files in it.

| Path | Holds |
| --- | --- |
| `Gemfile` | `skyward` at the version that wrote the app, `sqlite3`, Falcon to serve the app in development (`skyward serve`) and in production, and Steep, rbs-inline, Minitest and Rake |
| `boot.rb` | loads `modules/` with Zeitwerk, eager loads it and connects to `DATABASE_URL`, or SQLite at `db/todos.sqlite3` without it |
| `app.rb` | requires `boot.rb` and assigns `App = Skyward.app(docs: true, ...)`, wiring each API to its collaborators |
| `config.ru` | runs `App` |
| `modules/notes/` | one small resource to copy: `Notes::Record`, a table class, and `Notes::API`, its typed endpoints |
| `db/migrate/` | the migration `skyward migration` wrote for `Notes::Record` |
| `sig/generated` | the signatures rbs-inline generates from the app's inline annotations |
| `Steepfile`, `rbs_collection.yaml` | Steep with every diagnostic an error, and the gem signatures it reads |
| `test/` | tests of `Notes::API` and of `App` over HTTP, each in a transaction that's rolled back, on in-memory SQLite or `TEST_DATABASE_URL` |
| `bin/setup` | installs the gems and the gem signatures, and migrates the database |
| `bin/test` | runs the tests |
| `bin/ci` | regenerates the signatures and fails if they changed, runs the tests, then runs `skyward check` on a database of its own |
| `AGENTS.md` | the app's conventions: an endpoint is a method, signatures are generated, outcomes are values matched with `case`/`when`, collaborators are wired in `app.rb`, migrations are generated and reviewed, and `bin/ci` runs before pushing |
| `.gitignore` | the database, the installed gem signatures and the bundle |

```sh
$ cd todos
$ bin/setup
$ bundle exec skyward serve   # http://localhost:9292/docs
```

The app is an API with no frontend. Its consumers generate their clients from its OpenAPI document, at `/openapi.json`.

[The getting-started guide](../docs/getting-started.md) walks through an app step by step, from `skyward new` to a new column, a new endpoint, its tests, `bin/ci` and the OpenAPI document.

## Status

This README is the spec, and this section lists each part of it that's built, as it lands. `require "skyward"` loads both gems.

- **One reading of each type.** The `skyward` gem's tests hold Skyward API and Skyward ORM to the promise both READMEs make, that a row read from the database and the same class sent as JSON are the same thing, on SQLite and on PostgreSQL. A table class with a column of every type both read (`Integer`, `Float`, `String`, `bool`, `Date`, `Time` and a union of symbols, and a nullable one of each) makes the round trip: a row the ORM inserts, returned from an endpoint typed with the class, read back with `Skyward::API::Test.client` and posted to an endpoint that takes the class as `body:`, arrives `==` to the row the database holds, a `Time` with microseconds and a non-UTC offset included. The class's OpenAPI component and the ORM's columns agree, field by field, on name, type, nullability and enum values. The types only one gem reads are listed in the test, so teaching either gem a type means updating the list: for now `Hash[String, T]`, `Array[T]`, records, classes with typed readers, unions of them and literals are read by Skyward API alone, and `BigDecimal` by neither.
- **`skyward new`.** `skyward new NAME` writes the app [Starting an app](#starting-an-app) describes, every file of it from a function of the name alone, then runs `bundle install` in it unless given `--skip-bundle`. A missing name, more than one, a name that isn't lowercase letters, digits and underscores starting with a letter, or a path that exists and isn't an empty directory prints why and exits 1, writing nothing. The packaging check builds and installs the gems, runs `skyward new demo`, and fails unless the app's own `bin/ci` passes with them.
- **The getting-started guide and `llms.txt`.** [`docs/getting-started.md`](../docs/getting-started.md) walks a newcomer from `gem install skyward` to a running, tested, documented API, showing each step's command, code and output, for Skyward 0.3. [`llms.txt`](../llms.txt), at the repository root, points agents at the guide, each gem's README and the `AGENTS.md` that `skyward new` writes, as raw Markdown.
