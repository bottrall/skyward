# Contributing

Skyward is four gems in one repository. Each gem's `README.md` is its spec, and [`AGENTS.md`](AGENTS.md) holds the conventions for the code, for people and agents alike.

## Setup

You need the Ruby in `.ruby-version` for development. Skyward itself supports every Ruby that isn't end-of-life, and CI tests each one.

```sh
bin/setup
```

## Day to day

Everything runs through `bin/`, never a tool directly.

| Script                     | Does                                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `bin/setup`                | installs the dev bundle, each gem's and example's own bundle, and the gem signatures Steep uses                                       |
| `bin/test [paths]`         | runs every gem's and example's tests, each in its own bundle, and the release tooling's; pass files or directories to run only those |
| `bin/lint [--fix] [paths]` | runs RuboCop; `--fix` autocorrects what it can                                                                                        |
| `bin/typecheck`            | checks the signatures and the RBS collection are current, then runs Steep on every gem and example                                    |
| `bin/generate [--watch]`   | regenerates each gem's and example's `sig/generated` from its inline annotations; `--watch` regenerates them on every change          |
| `bin/build`                | builds the gems into `pkg/`, installs and loads them, and runs the `bin/ci` of the app `skyward new` writes with them                 |
| `bin/check`                | `bin/lint --fix`, then `bin/typecheck`, then `bin/test`: run it before calling a change done                                          |
| `bin/ci`                   | runs exactly what CI runs, without fixing anything: run it before you push                                                            |

## PostgreSQL

Skyward ORM's tests, and the `skyward` gem's tests that check Skyward API and Skyward ORM read types the same way, run on SQLite unless `TEST_DATABASE=postgresql` says to run them on PostgreSQL. Either way, the PostgreSQL adapter's own tests need a PostgreSQL, at `TEST_POSTGRES_URL`, so `bin/test` and `bin/ci` do too. Before each test that uses it, the suite drops that database's `public` schema and closes its other connections, and `bin/test` drops it again before it runs [`examples/todos_postgres`](examples/todos_postgres/README.md)'s tests there, so give it a database of its own, such as one in a container. A test that switches between two databases empties a second one the same way, beside it on the same server, named after it with `_second`, which it creates the first time:

```sh
docker run -d --rm --name skyward-postgres -e POSTGRES_PASSWORD=postgres -p 54320:5432 postgres:17
export TEST_POSTGRES_URL=postgres://postgres:postgres@localhost:54320/postgres

bin/test                            # the suites on SQLite
TEST_DATABASE=postgresql bin/test   # and on PostgreSQL

docker stop skyward-postgres
```

CI runs both suites both ways, on every supported Ruby. Each example runs on its own database alone, whatever `TEST_DATABASE` says: [`examples/todos`](examples/todos/README.md) on SQLite, and `examples/todos_postgres` on PostgreSQL.

## Pull requests

PR titles are [Conventional Commits](https://www.conventionalcommits.org/) with a scope naming the gem they change (`feat(api): add providers`, `fix(orm): quote column names`), because each becomes a squash commit on `main` and the changelog is built from them. Fill in the PR template.

## Releasing

The gems release together, at one version, through [release-please](https://github.com/googleapis/release-please). Every push to `main` updates its release PR, which bumps every gem's version, adds the changelog section and updates the lockfiles. Merging that PR tags the release, and `release.yml` then checks the versions, builds and installs the gems, and publishes them with RubyGems trusted publishing. There's nothing to run by hand.
