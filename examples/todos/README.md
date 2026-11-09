# Todos

A JSON API for todos, built with [Skyward API](../../skyward-api/README.md) and stored with [Skyward ORM](../../skyward-orm/README.md). It's Skyward's end-to-end test: its HTTP tests run on SQLite and on PostgreSQL, which proves the two halves work together in a real app.

It has no frontend. Its tests and `/docs` exercise it, and a client is whatever you generate from its OpenAPI document at `/openapi.json`.

---

## Contents

- [Layout](#layout)
- [Endpoints](#endpoints)
- [Running it](#running-it)
- [Testing it](#testing-it)
- [Checking it](#checking-it)

---

## Layout

The code is grouped by domain. `boot.rb` loads `lib/` and `modules/` with Zeitwerk, eager loads them, and calls `Skyward.connect`.

| Path                       | Holds                                                                              |
| -------------------------- | ---------------------------------------------------------------------------------- |
| `boot.rb`                  | loads the app's code and connects to `DATABASE_URL`, or `db/todos.sqlite3` without it |
| `app.rb`                   | requires `boot.rb` and assigns `App`, wiring each API to its collaborators          |
| `config.ru`                | runs `App`                                                                         |
| `lib/health_api.rb`        | `HealthAPI`, for load balancers and uptime checks                                  |
| `modules/lists/record.rb`  | `Lists::Record`, the `lists` table                                                 |
| `modules/todos/record.rb`  | `Todos::Record`, the `todos` table                                                 |
| `modules/todos/service.rb` | `Todos::Service`, the queries and writes                                           |
| `modules/todos/api.rb`     | `Todos::API`, the `/todos` endpoints, which return `Todos::Record` rows directly    |
| `db/migrate/`              | the migration `skyward migration` wrote from the table classes, committed as written |
| `sig/`                     | `sig/generated` from the inline annotations (`bin/rbs`), and `sig/manual`          |
| `Steepfile`                | what `skyward check` type-checks                                                   |

`Todos::Record` uses each of the ORM's declarations: a reference to `Lists::Record` that cascades on delete, defaults for `priority` and `done`, a check on the title's length, a symbol union for `priority` and an index on `list_id` and `done`.

---

## Endpoints

| Endpoint                   | Does                                                                                   |
| -------------------------- | -------------------------------------------------------------------------------------- |
| `GET /up`                  | says the app is up                                                                     |
| `GET /todos`               | lists todos, newest first: `done=true` or `done=false` filters them, and `limit` caps them at 50 by default |
| `GET /todos/:id`           | answers a todo, or 404                                                                 |
| `POST /todos`              | creates a todo from `title`, `priority` (`low`, `normal` or `high`), and an optional `due_on` and `list_id` |
| `POST /todos/:id/complete` | marks a todo as done, or 404                                                           |
| `DELETE /todos/:id`        | deletes a todo, or 404                                                                 |

`POST /todos` answers 201 with the todo, 404 when `list_id` names a list that doesn't exist, and 422 when the title is empty or longer than 200 characters. The database enforces both: the service turns the `Skyward::ORM::Violation` into a symbol, and the endpoint matches it with `case`/`when` to answer 404 or 422.

`/openapi.json` is the OpenAPI document, and `/docs` is its API reference.

---

## Running it

Run `bin/setup` at the repository's root first. Then, from `examples/todos`:

```sh
bundle exec skyward migrate   # creates db/todos.sqlite3 and its tables
bundle exec skyward serve     # http://localhost:9292/docs
```

`PORT` picks another port for `skyward serve`. After changing a table class, `bundle exec skyward migration NAME` writes the migration that brings the database in line with it.

### On PostgreSQL

`skyward migration` writes SQL for the database it connects to, so the committed migration is SQLite's, and PostgreSQL needs its own. Generate it in place of SQLite's, with `DATABASE_URL` naming the database:

```sh
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/todos
rm db/migrate/*.sql
bundle exec skyward migration create_lists_and_todos
bundle exec skyward migrate
bundle exec skyward serve
```

Don't commit the PostgreSQL migration: `git checkout db/migrate` puts SQLite's back.

---

## Testing it

```sh
bundle exec rake test
```

The tests run on an in-memory SQLite database of their own, migrated from empty each run. To run them on PostgreSQL, generate its migration as [On PostgreSQL](#on-postgresql) describes, then point `TEST_DATABASE_URL` at an empty database, which the tests migrate. The tests never read `DATABASE_URL`, so they can't touch the app's database:

```sh
TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/todos_test bundle exec rake test
```

Every test runs in a transaction that's rolled back after it, the HTTP tests included, so each starts from an empty database. `bin/test` at the repository's root runs them too, with every gem's.

---

## Checking it

```sh
bundle exec skyward check
```

checks that `sig/generated` is current, boots `app.rb` in strict mode and runs Steep with this directory's `Steepfile`. The boot connects, so it needs a migrated database: run `bundle exec skyward migrate` first, with the same `DATABASE_URL`. CI runs it on every change.
