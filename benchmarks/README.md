# Benchmarks

How fast Skyward API answers requests and Skyward ORM reads rows, and how many objects each allocates, so a change can show it made them faster. They measure what [`skyward-api/README.md` → Production](../skyward-api/README.md#production) and [`skyward-orm/README.md` → Performance](../skyward-orm/README.md#performance) claim. Every release attaches a run to its GitHub release, as `benchmarks-vX.Y.Z.json` and `.md`, and a performance PR shows a run before and after, on one machine, in its Proof.

```sh
bin/bench                # every scenario
bin/bench api            # those whose names start with api
bin/bench orm.sqlite     # or with orm.sqlite
```

`bin/bench` runs with YJIT on, as apps run in production, unless `RUBY_YJIT_ENABLE` says otherwise. It exits 1, before it times anything, when no scenario's name starts with one of the names it's given.

---

## Scenarios

| Scenario | Times |
| --- | --- |
| `api.get` | `GET /todos/42`, an `id: Integer` from the path, answered with a `Todo` from an in-memory store |
| `api.post` | `POST /todos`, a JSON body coerced into `body: NewTodo`, answered with `Responses::Created[Todo]` |
| `api.not_found` | `GET /nope` on the same app, a 404 |
| `api.routes.first` | a route of the first of ten mounts of a 20-route API, so 200 endpoints |
| `api.routes.last` | the same route of the last mount |
| `api.routes.not_found` | a path no route matches |
| `orm.sqlite.rows.1`, `.rows.100`, `.rows.1000` | `limit(n).to_a` on a table of six columns and 1,000 rows, so the three separate a query's fixed cost from its cost per row |
| `orm.sqlite.find_by` | `find_by(id:)` |
| `orm.sqlite.build` | building `where(done: false, id: 1..).order(:id).limit(20)`'s SQL without running it |
| `orm.postgresql.*` | the same, on PostgreSQL |

The API scenarios call the app built by `Skyward.app` directly, as a Rack server would, with no server or network, and read and close each response's body. The app has `Skyward.app`'s defaults, but for a logger that drops each request's log line once it's built.

The ORM scenarios run on an in-memory SQLite database, and on the PostgreSQL at `TEST_POSTGRES_URL`, the one [`CONTRIBUTING.md`](../CONTRIBUTING.md#postgresql) has you give the tests. They drop and recreate their own table there, `bench_tasks`, and are skipped without it, which the output and the results say.

The API scenarios, the SQLite ones and the PostgreSQL ones each run in a Ruby of their own, so one group's garbage and JIT warmup never land in another's numbers.

---

## Results

Before anything is timed, `bin/bench` runs each scenario once and checks its answer: the status and a body field for a request, and the row count and the first row's id for a query. When one is wrong, it exits 1 naming the scenario and what it answered, so a benchmark never times a 500 or an empty result.

It then prints [benchmark-ips](https://github.com/evanphx/benchmark-ips)'s report as it goes, and a Markdown table with, for each scenario:

- iterations per second, and their standard deviation
- requests per second for an API scenario, and rows per second for a `rows.*` one
- objects allocated per iteration, over 1,000 iterations after warmup

Speed on a shared machine varies by 10 to 20 percent from one run to the next, but the objects allocated don't vary with the machine, so they're the number to compare across releases.

It writes the same to `tmp/bench/results.json` and `tmp/bench/results.md`, with the environment: Skyward's version, the commit, `RUBY_DESCRIPTION`, whether YJIT was on, the CPU's model where `/proc/cpuinfo` has it, and SQLite's and PostgreSQL's versions.

---

## Layout

It's laid out like an example, with its own bundle and signatures. `boot.rb` loads `lib/` with Zeitwerk.

| Path | Holds |
| --- | --- |
| `run.rb` | what `bin/bench` runs: `Bench::Runner`, wired to a Ruby for each group |
| `group.rb` | one group's scenarios, checked, then timed, in a Ruby of its own |
| `lib/bench/runner.rb` | every group's checks, then every group timed, merged into one report |
| `lib/bench/groups.rb` | the groups and their scenarios, which a run's names select, and which it skips |
| `lib/bench/environment.rb` | what a run's numbers depend on |
| `lib/bench/todos_api.rb`, `lib/bench/routes_api.rb` | the API scenarios' API classes |
| `lib/bench/requests.rb` | the API scenarios |
| `lib/bench/task.rb` | `Bench::Task`, the ORM scenarios' table |
| `lib/bench/queries.rb` | the ORM scenarios, and the rows they're seeded with |
| `lib/bench/measure.rb` | each scenario's check, and its timing with benchmark-ips |
| `lib/bench/results.rb` | the results, as JSON and Markdown |
| `db/sqlite/`, `db/postgresql/` | each database's migration, which `Skyward.migrate` runs before the rows are seeded |

Its tests run each scenario once against its check, on both databases, and test the results it writes, without timing anything. `bin/test` runs them with every gem's, and CI on every change.
