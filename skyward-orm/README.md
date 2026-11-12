# Skyward ORM

> [!CAUTION]
> Skyward ORM is pre-1.0. This README is its spec, most of it is built, and [Status](#status) lists exactly what is. Any release may change the API, so don't run it in production yet.

A Ruby ORM for PostgreSQL and SQLite where **a class is a table and its rows are values**.

You write a plain Ruby class with a typed reader for each column, and tell Skyward ORM which table it lives in. From then on the class is the table: you query it and write to it, and Skyward ORM writes its migrations from it. Rows come back as frozen instances of your class. There are no callbacks, no dirty tracking and no lazy loading, so you get your data and the SQL that fetched it.

It's half of Skyward. The other half is [Skyward API](../skyward-api/README.md), and you can use either without the other.

```ruby
# rbs_inline: enabled
require "skyward/orm"

class Todo < Skyward::ORM::Record
  table :todos
  default done: false

  # @dynamic id, title, done
  attr_reader :id     #: Integer
  attr_reader :title  #: String
  attr_reader :done   #: bool
end

Skyward.connect("sqlite://todos.db")

Todo.into(Todo).insert(title: "Buy milk")
# => #<Todo id=1, title="Buy milk", done=false>

Todo.where(done: false).map(&:title)
# => ["Buy milk"]

Todo.where(id: 1).update(done: true)
# => 1
```

```sh
$ skyward migration create_todos   # writes the CREATE TABLE for you, from the class
$ skyward migrate
```

---

## Contents

- [Install](#install)
- [Tables](#tables)
- [Migrations](#migrations)
- [Connecting](#connecting)
- [Reading](#reading)
- [Projections, joins and aggregates](#projections-joins-and-aggregates)
- [Raw SQL](#raw-sql)
- [Writing](#writing)
- [Transactions](#transactions)
- [Types](#types)
- [Testing](#testing)
- [Performance](#performance)
- [CLI](#cli)
- [Coming from other libraries](#coming-from-other-libraries)
- [Design principles](#design-principles)
- [Status](#status)

---

## Install

```ruby
# Gemfile
gem "skyward-orm"
gem "pg"       # or "sqlite3"
```

Skyward ORM supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026), and PostgreSQL and SQLite.

---

## Tables

A table is a plain Ruby class that subclasses `Skyward::ORM::Record`. Each `attr_reader` is a column, and its `#:` comment is the column's type. In an app organised by domain, name it after what it is: `Todos::Record`, `Lists::Record`.

```ruby
# rbs_inline: enabled

class Todo < Skyward::ORM::Record
  table :todos
  references :list_id, List, on_delete: :cascade
  default priority: :normal, done: false, created_at: Skyward.sql("now()")
  check :title, length: 1..200
  index :list_id, :done

  # @dynamic id, list_id, title, priority, due_on, done, created_at
  attr_reader :id          #: Integer
  attr_reader :list_id     #: Integer
  attr_reader :title       #: String
  attr_reader :priority    #: :low | :normal | :high
  attr_reader :due_on      #: Date?
  attr_reader :done        #: bool
  attr_reader :created_at  #: Time

  # @rbs today: Date
  # @rbs return: bool
  def overdue?(today = Date.today) = !done && !due_on.nil? && due_on < today
end
```

**The class is the table.** Everything at class level describes or queries `todos`. **An instance is a row**, and Skyward ORM makes it a value: it's frozen, compares with `==`, and has `to_h`, `with` and pattern matching. You build one with `Todo.new(id: 1, title: "Milk", ...)`. Leave out a column and it raises. It's safe to share between threads, cache, return from a Skyward API endpoint, or build in a test.

The `# @dynamic` line lists the columns for Steep, which doesn't count an `attr_reader` as defining a method.

Methods are just methods. `overdue?` is ordinary Ruby, and a computed value is a `def`, because on a table an `attr_reader` always means a column.

The class body is the schema, so everything about the table is in one place:

| Declaration                              | Means                                                         |
| ---------------------------------------- | ------------------------------------------------------------- |
| `table :todos`                           | the rows live in `todos`                                      |
| `primary_key :uuid`                      | the primary key, if it isn't `:id`                            |
| `references :list_id, List`              | a foreign key to `List`'s primary key (`on_delete:` optional) |
| `default done: false`                    | column defaults; `Skyward.sql("...")` for an SQL expression    |
| `unique :email`                          | a unique constraint, on one or more columns                   |
| `check :title, length: 1..200`           | a check constraint on the column's length; `check :title, Skyward.sql("...")` for any other SQL expression |
| `index :list_id, :done`                  | an index, on one or more columns                              |

A declaration that names a column the class doesn't have is caught when you connect, or generate a migration, and the error points at it, with the closest column the class has:

```
Skyward::Core::BootError: Todo has no column lsit_id, which its index names. Add `attr_reader :lsit_id`, or fix the name.

    app/todo.rb:7
    index :lsit_id, :done
          ^^^^^^^^
Did you mean list_id?
```

Column types come from the `#:` comments, the same types Steep reads. `T?` means a nullable column, everything else is `NOT NULL`, and a symbol union such as `:low | :normal | :high` gets a check constraint for its values.

An `Integer` is a `bigint` and a `String` is `text`, so for a `uuid` column, or a narrower integer, Skyward ORM declares three aliases: `uuid`, `int32` and `int16`. Steep reads each as the type it names, a `String` or an `Integer`, and Skyward ORM as its own column type, so the type stays in the `#:` comment:

```ruby
# rbs_inline: enabled
# @rbs use Skyward::ORM::*

class User < Skyward::ORM::Record
  table :users
  default id: Skyward.sql("gen_random_uuid()")

  # @dynamic id, logins, invited_by
  attr_reader :id          #: uuid
  attr_reader :logins      #: int32
  attr_reader :invited_by  #: uuid?
end
```

A `uuid` primary key takes its `default`, and an `int32` or `int16` one is numbered as an `Integer` one is. Rows hold a `uuid` as a String and an `int32` or `int16` as an Integer. Steep can't tell a `uuid` from any other String, so Skyward ORM checks the values instead: a `uuid` that isn't 8-4-4-4-12 hex digits, or an `int32` or `int16` outside its range, raises an `ArgumentError` naming the column as the query or write is built.

---

## Migrations

You don't write migrations by hand. Change the class, and Skyward ORM writes the SQL that changes the database to match:

```
$ skyward migration create_todos
Todo has no table yet:
  + todos  7 columns, 1 reference, 2 checks, 1 index
Wrote db/migrate/20261018093000_create_todos.sql. Review it, then run `skyward migrate`.
```

```sql
-- db/migrate/20261018093000_create_todos.sql
CREATE TABLE todos (
  id          bigint GENERATED ALWAYS AS IDENTITY CONSTRAINT todos_pkey PRIMARY KEY,
  list_id     bigint      NOT NULL CONSTRAINT todos_list_id_fkey REFERENCES lists ON DELETE CASCADE,
  title       text        NOT NULL CONSTRAINT todos_title_check CHECK (length(title) BETWEEN 1 AND 200),
  priority    text        NOT NULL DEFAULT 'normal' CONSTRAINT todos_priority_check CHECK (priority IN ('low', 'normal', 'high')),
  due_on      date,
  done        boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX todos_list_id_done_index ON todos (list_id, done);

-- down
DROP TABLE todos;
```

Later, add `:notes #: String?` to `Todo` and run it again:

```
$ skyward migration add_notes_to_todos
Todo differs from the todos table:
  + notes  text NULL
Wrote db/migrate/20261019141500_add_notes_to_todos.sql. Review it, then run `skyward migrate`.
```

```sql
-- db/migrate/20261019141500_add_notes_to_todos.sql
ALTER TABLE todos ADD COLUMN notes text;

-- down
ALTER TABLE todos DROP COLUMN notes;
```

Any other change to the class works the same way. Rename `notes` to `details`, make `due_on` a `Date`, and add `index :due_on`:

```
$ skyward migration rework_todos
Did you rename todos.notes to todos.details? [y/N] y
Todo differs from the todos table:
  ~ details             renamed from notes
  ~ due_on              NOT NULL, was NULL
  + todos_due_on_index  index (due_on)
Wrote db/migrate/20261020110000_rework_todos.sql. Review it, then run `skyward migrate`.
```

```sql
-- db/migrate/20261020110000_rework_todos.sql
ALTER TABLE todos RENAME COLUMN notes TO details;
-- TODO: backfill the NULLs in todos.due_on before it becomes NOT NULL
ALTER TABLE todos ALTER COLUMN due_on SET NOT NULL;
CREATE INDEX todos_due_on_index ON todos (due_on);

-- down
DROP INDEX todos_due_on_index;
ALTER TABLE todos ALTER COLUMN due_on DROP NOT NULL;
ALTER TABLE todos RENAME COLUMN details TO notes;
```

The summary marks what's added `+`, dropped `-` and changed `~`: columns, their types, `NULL`s and defaults, and indexes, uniques, checks and references.

- **Every constraint and index has a name.** It's the table, the columns and the kind, such as `todos_title_check`, so a [`Violation`](#when-the-database-says-no) names the same constraint on PostgreSQL and SQLite.
- **A constraint under another name is renamed.** A database Skyward ORM didn't make names its constraints its own way, such as Rails's `fk_rails_0123456789`. A unique or a reference that does what the class declares, on the same columns, to the same table and with the same `ON DELETE`, is renamed to its Skyward ORM name, shown as `~ todos_list_id_fkey  renamed from fk_rails_0123456789`, rather than dropped and added back, which would lock the table and check every row. PostgreSQL renames it with `ALTER TABLE todos RENAME CONSTRAINT fk_rails_0123456789 TO todos_list_id_fkey`, and SQLite, which can't rename one, rebuilds the table. A check's expression can't be compared, so a check under another name is dropped and added.
- **Migrations are plain SQL files you commit.** Read them, edit them, and add data backfills to the same file. Skyward ORM runs each one once, in order, inside a transaction. `skyward rollback` runs the `-- down` section.
- **Every change has a down.** A dropped column comes back in the down section with a comment that its data isn't restored, since dropping it lost that.
- **Skyward ORM asks when it can't know what you meant.** If a column disappears and another of a compatible type appears, it asks whether you renamed it, rather than dropping your data. Yes renames it, and no drops one and adds the other. With no terminal to ask, as in CI, it writes nothing, and names the columns to run it again for in a terminal.
- **Generation needs types.** A column without a `#:` type still works at runtime, but Skyward ORM can't guess its SQL type. The migration gets `-- TODO: todos.notes needs a type`, and you write that line yourself.
- **A new required column needs a default.** The rows already in the table need a value for it, so the migration gets `-- TODO: todos.notes needs a DEFAULT for the rows todos already has`. Give it one, or make the column nullable.
- **A column made required needs its `NULL`s filled.** The migration gets `-- TODO: backfill the NULLs in todos.due_on before it becomes NOT NULL`, where your `UPDATE` goes.
- **SQLite rebuilds a table to change it.** SQLite's `ALTER TABLE` adds, drops and renames columns, but can't change one or its constraints, so the migration creates the new table, copies the rows, drops the old table, renames the new one and recreates its indexes. The new table keeps each index and constraint the class can't declare. Dropping a table runs the `ON DELETE` of every table that references it, and SQLite only turns foreign keys off outside a transaction, so `skyward migrate` and `skyward rollback` run each SQLite migration with `PRAGMA foreign_keys = OFF`, and check them with `PRAGMA foreign_key_check` before they commit. The rows that reference a rebuilt table stay as they were.
- **A table with no class is never dropped.** A class that isn't loaded looks the same as one that's gone, so `skyward status` reports the table instead.
- **What a class can't declare is kept.** That's an index on an expression, with a `WHERE` or unique, or on PostgreSQL one by a method other than `btree` or with `INCLUDE`. It's also a check on no column or on more than one, and a foreign key on more than one column or to a column that isn't its table's primary key. Skyward ORM never drops or adds one, so a hand-written migration adds it, and drops it too. `skyward status` lists each one under its table.
- **Hand-written migrations are always an option.** `skyward migration --empty backfill_priorities` gives you an empty file for SQL you write yourself.
- **A generated column is hand-written.** A class can't say how the database generates a column, such as `search text GENERATED ALWAYS AS (lower(title)) STORED`, so you add and change one with `skyward migration --empty`, and `skyward migration` never drops one or compares its expression. SQLite rebuilds a table from its class, which would lose the column, so a change that rebuilds a table with one is refused too: write that migration with `--empty`. Write its migration first, then give it an `attr_reader` and a type like any other column, and `Skyward.connect` checks its type and nullability.

Business rules like the title length live in the database, where they hold for every writer, and they come back to Ruby as a [`Violation`](#when-the-database-says-no).

---

## Connecting

```ruby
Skyward.connect(ENV.fetch("DATABASE_URL"), pool: 10)
```

Call it once, where your app boots. Skyward ORM reads your column types from the `.rbs` files under `sig/`, or the directory you pass as `signatures:`.

Like ActiveRecord, Skyward ORM keeps the connection for you, so `Todo.where(...)` just works. It also gives you what makes that safe: tests that each run in a rolled-back transaction, and `Skyward.using(other_database) { ... }` to switch databases for one block. The switch applies to the current fiber and the fibers and threads it starts in the block, never globally.

When you connect, Skyward ORM compares every loaded table class with the live schema and refuses to start if they disagree:

```
Skyward::ORM::SchemaMismatch: Todo doesn't match the todos table

  notes  todos has no column notes.
         Run `skyward migrate`, or `skyward migration` if you haven't generated one.
```

It looks for each table and column the class declares, and for a typed column, a compatible type and the same nullability. A column without a type only has to be there. Columns the class doesn't declare, indexes and constraints aren't compared, and `skyward status` lists those differences. A table class loaded after connect is checked the first time it's used.

`Skyward.connect(url, check: false)` skips the check, for what fixes a mismatch. The migration commands turn it off for their process before they boot your app, so the `Skyward.connect(url)` in your `boot.rb` needs no change, and `Skyward.migrate` runs the check once it has migrated.

### A second database

A read replica, or a second primary, is another `Skyward.connect`, with `default: false` so it doesn't replace the database every query uses. It returns the database, which you keep in a constant or inject into what needs it:

```ruby
Skyward.connect(ENV.fetch("DATABASE_URL"), pool: 10)
REPLICA = Skyward.connect(ENV.fetch("REPLICA_URL"), pool: 10, default: false) #: Skyward::ORM::Database

Skyward.using(REPLICA) { Todo.where(done: false).to_a }
```

It has its own pool, up to its own `pool:`, and its own `signatures:` and `check:`. Connecting checks every loaded table class against its schema too, so a replica a migration hasn't reached fails at boot, and a table class loaded later is checked against each database the first time it's used there.

`Skyward.using(database) { ... }` makes `database` current for its block and returns the block's value. Every query, write, `Skyward.transaction`, `Skyward.query` and `Skyward.migrate` in the block uses it, and the previous database is current again when the block ends, however it ends. An inner `Skyward.using` switches again for its own block. Anything but a database `Skyward.connect` returned, or no block, raises `ArgumentError`.

The switch is held in fiber storage, so another request under Puma or Falcon keeps its own database, while the fibers and threads the block starts inherit it, each checking out its own connection. A query runs on the database that's current when it runs, so return rows (`to_a`) from the block, not a query.

### Instrumenting

`instrument:` takes a hook that Skyward ORM wraps around every statement it sends, so you can log the SQL while you debug, or put an APM span around it:

```ruby
log_sql = lambda do |execution, &run|
  ms = run.call
  LOGGER.debug(format("%.1fms  %s", ms, execution.sql))
end

Skyward.connect(ENV.fetch("DATABASE_URL"), instrument: log_sql)
```

```ruby
trace_sql = lambda do |execution, &run|
  attributes = { "db.system.name" => execution.adapter.to_s, "db.query.text" => execution.sql }
  TRACER.in_span("sql", kind: :client, attributes:) { run.call }
end
```

The hook is anything that responds to `call(execution) { ... }`, such as a lambda with a `&block` parameter, or an object. Skyward ORM calls it before the statement is sent, and the statement runs when the hook calls its block. The block returns how long the statement took in milliseconds, as a Float, timed around the driver's call alone, so waiting for a pooled connection isn't counted. The hook's own return value is ignored, so it needn't pass anything through. Anything without `call` raises `Skyward::Core::BootError` before `Skyward.connect` connects. Without `instrument:`, the pool's connections are the adapter's own, so an app with no hook pays nothing for it.

The execution is a frozen `Skyward::ORM::Execution`, whose `sql` and `binds` are frozen copies of what's sent, so the hook can't rewrite the SQL or the list of binds:

- `sql`, the statement as sent, with the adapter's placeholders (`$1` or `?`).
- `binds`, the values bound to it, encoded as the adapter sends them, as `to_sql` shows them.
- `adapter`, `:postgresql` or `:sqlite`.

It has no row count and no table class: the SQL names the table, and its first word is the operation.

Every statement sent on a pooled connection is reported, in the order it's sent: queries, `count` and `exists?`, writes, `Skyward.query`, the `BEGIN`, `SAVEPOINT`, `RELEASE`, `COMMIT` and `ROLLBACK` of `Skyward.transaction` and `Skyward::ORM::Transactional`, the `ROLLBACK` the pool sends a connection that comes back mid-transaction, migrations and their bookkeeping, and the schema reads at connect and after migrating. A migration's up section is one statement, with no binds. A statement's transaction shows in the `BEGIN` and `SAVEPOINT` reported before it, on the same fiber. Opening a connection isn't reported: the session setup each adapter runs, such as SQLite's `PRAGMA foreign_keys = ON`, happens before the connection joins the pool.

**`binds` hold your users' data**, such as their emails and names. Skyward ORM can't redact them, since raw SQL's binds name no column, so your hook decides what leaves the process: log them only while you debug, on your own machine. The examples above send `sql` alone, which holds no values when every value is bound, as it is in every query and write Skyward ORM builds. It isn't when the SQL itself has one: `Skyward.query` with a value interpolated into its SQL, a migration's up section, and the `Skyward.sql` expressions a migration writes for `default` and `check` all send their literals in `sql`.

A statement that fails raises the driver's exception out of the block, so an APM span records it, and Skyward ORM then handles it as it would without a hook: a constraint the database refuses still comes back as a `Skyward::ORM::Violation`. The hook sees the driver's error, such as `PG::UniqueViolation`, not the violation. Its message can hold the values it refused, as `PG::UniqueViolation`'s `Key (email)=(ada@example.com) already exists` does, so a span should record the exception's class rather than its message, or redact the message first.

A hook that raises raises out of the statement, wherever that statement is. Before the hook calls its block, the statement hasn't run. After, it has, and outside a transaction its write stays. Skyward ORM handles the hook's exception wherever it handles the statement's own: a query or write raises it, `Skyward.transaction` rolls back, the pool closes a connection whose `ROLLBACK` raised, and a migration that can't begin raises `Skyward::ORM::MigrationError`. A hook that never calls its block, or calls it twice, raises a `RuntimeError` saying the hook must call its block once, and the second call runs nothing.

The hook runs on the fiber that runs the statement, so an APM SDK's current span parents it, and it can read what your app keeps in fiber storage. Skyward API keeps its request ID in the Rack env, so a few lines of middleware put it where a hook can read it:

```ruby
class RequestIdInFiber
  def initialize(app)
    @app = app
  end

  def call(env)
    Fiber[:request_id] = env["skyward.request_id"]
    @app.call(env)
  end
end

App = Skyward.app do |app|
  app.use RequestIdInFiber
  app.mount TodosAPI.new, at: "/todos"
end

log_sql = lambda do |execution, &run|
  ms = run.call
  LOGGER.debug(format("[%s] %.1fms  %s", Fiber[:request_id], ms, execution.sql))
end
```

A query the hook itself runs through Skyward ORM is reported too, so the hook recurses: one that writes its log to the database has to skip its own statements, such as with a flag it sets in fiber storage around them.

---

## Reading

Every query starts at the table. Queries are immutable: each method returns a new query, and nothing runs until you ask for rows.

```ruby
open = Todo.where(done: false).order(created_at: :desc)

open.limit(20).to_a       # => Array[Todo]
open.first                # => Todo or nil
open.count                # => Integer, via COUNT(*)
open.exists?              # => bool
Todo.find_by(id: 42)      # => Todo or nil
Todo.all                  # => every row, as a query
```

Queries are `Enumerable`, so `each`, `map`, `group_by` and friends work, and they run the query once. `where` filters in SQL. `select` and `filter` filter in Ruby after fetching, just as they do on an `Array`.

`where` takes the hash conditions you already know, plus the Ruby values that naturally mean something in SQL:

| Ruby                                     | SQL                                                           |
| ---------------------------------------- | ------------------------------------------------------------- |
| `where(done: false)`                     | `done = false`                                                |
| `where(due_on: nil)`                     | `due_on IS NULL`                                              |
| `where(priority: [:high, :normal])`      | `priority IN ('high', 'normal')`                              |
| `where(due_on: ..Date.today)`            | `due_on <= '2026-10-18'`                                      |
| `where(due_on: Date.today...)`           | `due_on >= '2026-10-18'`                                      |
| `where(created_at: from...to)`           | `created_at >= ? AND created_at < ?`                          |
| `exclude(done: true)`                    | `NOT (done = true)`                                           |
| `where(done: false).or(priority: :high)` | `done = false OR priority = 'high'`                           |
| `where(payload: nil)`                    | `payload IS NULL`                                             |
| `where(tags: nil)`                       | `tags IS NULL`                                                |
| `where("title ILIKE ?", "%milk%")`       | `(title ILIKE '%milk%')`, with the value bound as a parameter |

A range with only one end compares with that end alone, and a range with neither end raises `ArgumentError`. On SQLite, a range on a `BigDecimal` column, and `order` by one, compare it as a `REAL`, since its text doesn't sort as numbers do (see [How types map](#how-types-map)). A `Hash[String, untyped]` column matches only `nil`, in `where`, `exclude` and `or`: PostgreSQL compares `jsonb` by value, but SQLite compares the JSON's text, so the two would return different rows for anything else. Any other value raises `ArgumentError`: `Webhook.payload is a Hash[String, untyped] column, which where matches only to nil. Match its contents with an SQL string.` So does an `Array[T]` column, where an Array would otherwise mean `IN`, which could mean either its items or the whole Array: `Todo.tags is an Array column, which where matches only to nil. Match its contents with an SQL string.` To find a row by one item, write `where("? = ANY(tags)", "milk")` on PostgreSQL, or `where("EXISTS (SELECT 1 FROM json_each(tags) WHERE value = ?)", "milk")` on SQLite. An SQL string goes in parentheses, and each `?` in it binds the next value, numbered on from the query's other values in the connected database's placeholder style. A `?` inside a quoted string, a quoted name or a comment is the SQL's own and is left as it is. When the query runs or shows its SQL, a count of `?` that doesn't match the values raises `ArgumentError`, and so does an `Array` or `Hash` value, which the driver would spread across several placeholders.

`exclude` takes what `where` takes and wraps it in `NOT (...)`. In SQL, `NOT` of a comparison with `NULL` is unknown, so it would leave out a row whose column is `NULL`, though that row doesn't match. So on a nullable or untyped column, `exclude` keeps the `NULL` rows: `exclude(due_on: Date.today)` is `(NOT (due_on = '2026-10-18') OR due_on IS NULL)`. A condition that matches `NULL` itself, such as `exclude(due_on: nil)`, is a plain `NOT`, and so is an SQL string, whose columns Skyward ORM can't know.

`or` takes what `where` takes and joins it to everything before it: `where(a).where(b).or(c)` is `(a AND b) OR c`, and a later `where(d)` makes it `((a AND b) OR c) AND d`. A query with no conditions has nothing to `or` with, and neither does an `or` given nothing, so each raises `ArgumentError`. An `exclude` given nothing keeps the query's conditions, but it no longer counts as an explicit `Todo.all` (see [Writing](#writing)).

Order and paging: `order(:title)`, `order(created_at: :desc)`, `limit(20)` and `offset(40)`.

### Scopes are class methods

Skyward ORM has no scope DSL, because Ruby already has methods, and the class is the table:

```ruby
# @rbs use Skyward::ORM::*

class Todo
  # @rbs return: Query[Todo]
  def self.open = where(done: false).order(created_at: :desc)

  # @rbs today: Date
  # @rbs return: Query[Todo]
  def self.overdue(today: Date.today) = open.where(due_on: ...today)
end

Todo.overdue.to_a
Todo.open.where(list_id: 3)                # start from a scope, then narrow it
Todo.where(list_id: 3).merge(Todo.open)    # or combine two queries with merge
```

A file that names Skyward ORM's types in its signatures starts with `# @rbs use Skyward::ORM::*`, so they can write `Query[Todo]` for `Skyward::ORM::Query[Todo]`.

`merge` adds another query's clauses to this one, as if each had been called after its own, so `Todo.where(list_id: 3).merge(Todo.open)` is `WHERE list_id = 3 AND done = false ORDER BY created_at DESC`. A side holding an `or` keeps it in parentheses: `where(a).merge(where(b).or(c))` is `a AND (b OR c)`. The other query's `order` and `group` follow this one's, its `limit` and `offset` replace this one's when it has them, and its joins follow this one's, with a join both make the same way kept once. A `Projection` merges a query and stays a projection, but a projection can't be merged into anything. Merging never widens a query, so the result can update or delete every row only when both queries are an explicit `Todo.all`.

### Seeing the SQL

Every query can show its SQL without running it:

```ruby
sql, binds = Todo.where(done: false, priority: [:high, :normal]).order(created_at: :desc).to_sql

puts sql
# SELECT "id", "list_id", "title", "priority", "due_on", "done", "created_at" FROM "todos"
# WHERE "done" = $1 AND "priority" IN ($2, $3) ORDER BY "created_at" DESC

binds # => [false, "high", "normal"]
```

Every table and column name is quoted, so a column named `order` or `user` works like any other. The placeholders and values are the ones the connected database is sent: on SQLite the placeholders are `?` and `false` is `0`. To see each statement Skyward ORM sends as it runs, and how long it took, give `Skyward.connect` a hook: see [Instrumenting](#instrumenting).

### Related rows

Skyward ORM has no associations, so nothing loads behind your back and N+1 queries can't hide. Loading related rows takes two queries and some `Enumerable`:

```ruby
lists = List.order(:name).to_a
todos = Todo.where(list_id: lists.map(&:id)).group_by(&:list_id)

lists.map { |list| ListWithTodos.new(**list.to_h, todos: todos.fetch(list.id, [])) }
```

---

## Projections, joins and aggregates

When you want a different shape, describe it with any class that takes keyword arguments (`Data` is the easiest) and select `into` it:

```ruby
TodoTitle = Data.define(:id, :title)

Todo.where(done: false).into(TodoTitle).to_a
# SELECT id, title FROM todos WHERE done = false
# => Array[TodoTitle]
```

A member reads the column with the same name. Anything else takes an SQL expression:

```ruby
TodoWithList = Data.define(:id, :title, :list_name)

Todo.join(List, list_id: :id).into(TodoWithList, list_name: "lists.name")
# SELECT todos.id, todos.title, lists.name AS list_name
# FROM todos JOIN lists ON todos.list_id = lists.id

OpenCount = Data.define(:list_id, :open)

Todo.where(done: false).group(:list_id).into(OpenCount, open: "count(*)")
# SELECT list_id, count(*) AS open FROM todos WHERE done = false GROUP BY list_id
```

An expression is raw SQL that goes into the query exactly as written, so it must be trusted: never build one from user input. Pass user input to `where`, which binds it as a parameter.

`into` returns a `Skyward::ORM::Projection[TodoTitle]`, a query like any other except that its writes return rows of its class (see [Writing](#writing)). It can come anywhere in a query, and `Todo.into(TodoTitle)` starts one from every row.

`join` is an inner join and `left_join` is a left join. A member without an expression reads from the table the query started from, so `id` above is `todos.id`. A joined table's columns always need an expression.

---

## Raw SQL

When a query is easier to write than to build, write it, and name the shape you want back:

```ruby
Overdue = Data.define(:title, :days_late)

Skyward.query(Overdue, <<~SQL, Date.today)
  SELECT title, current_date - due_on AS days_late
  FROM todos
  WHERE due_on < ? AND NOT done
  ORDER BY days_late DESC
SQL
# => Array[Overdue]
```

Values are always bound as parameters, never interpolated. If you leave out the class, you get an array of symbol-keyed hashes.

---

## Writing

A write returns how many rows it changed, unless you ask for rows with `into`. [Drizzle](https://orm.drizzle.team) is the model: a write gives nothing back unless you ask, so it never reads more than you use.

```ruby
Todo.insert(title: "Buy milk", list_id: 1)              # => 1
Todo.insert_all([{ title: "Eggs", list_id: 1 }, ...])   # => Integer, the rows inserted
Todo.where(id: 42).update(done: true)                   # => Integer, the rows updated
Todo.where(done: true).delete                           # => Integer, the rows deleted
```

`into` names the rows to return instead, through `RETURNING` of just its members' columns, or every column for the table class itself. It can come anywhere before the write. `insert` returns its one row, and `insert_all`, `update` and `delete` return an `Array`:

```ruby
Id = Data.define(:id)

Todo.into(Todo).insert(title: "Buy milk", list_id: 1)            # => Todo, every column
Todo.into(Id).insert(title: "Buy milk", list_id: 1)              # => Id, RETURNING "id"
Todo.into(Id).insert_all([{ title: "Eggs", list_id: 1 }, ...])   # => Array[Id], the inserted rows' ids
Todo.where(id: 42).into(Todo).update(done: true)                 # => Array[Todo], the updated rows
Todo.where(done: true).into(Id).delete                           # => Array[Id], the deleted rows' ids
```

`insert` and `insert_all` on a query take nothing but `into`. Anything else on the query, such as a `where`, an `order` or a join, raises an `ArgumentError` before any SQL runs.

`insert_all` doesn't promise its rows come back in the order they were given, because SQLite documents its `RETURNING` order as arbitrary and PostgreSQL doesn't promise one. When the order matters, return a column that tells the rows apart.

Columns with a default (`id`, `done`, `created_at`) and nullable ones (`due_on`) are optional. The rest are required, and leaving one out raises an `ArgumentError` straight away, as does a column the class doesn't have, a value its column's type doesn't take, or an Array or a Range, which is never one value but for an `Array[T]` column. A Hash for a `Hash[String, untyped]` column is one value, bound as its JSON to one placeholder, once each value in it is checked as [How types map](#how-types-map) says, and so is an Array for an `Array[T]` column, once each item in it is checked. A column without a type is left to the database, and `insert` with no columns inserts a row of defaults.

`insert_all` is one `INSERT` of every row, so a row that breaks a constraint inserts none of them, and the violation can't say which row it was. Each row is checked as `insert` checks one, and every row needs the first row's columns, in any order, so a row with others, or with none, raises an `ArgumentError` naming its index. So do more values than the database binds in one statement (65,535 on PostgreSQL and 32,766 on SQLite): split the rows, in a `Skyward.transaction` if they must land together. `insert_all([])` returns 0, or `[]` with `into`, without touching the database.

A column the database generates (see [Migrations](#migrations)) is read like any other, and never written. `insert` and `insert_all` don't need it, and `insert`, `insert_all` or `update` given it raises an `ArgumentError` before any SQL runs: `Todo.search is generated by the database, so it can't be written`.

`update` and `delete` change every row the query matches, so a query with no conditions would change the whole table. That raises an `ArgumentError`, unless the query is an explicit `Todo.all`, which says you mean every row. A `where` or `exclude` narrows it, even one given nothing, so it no longer counts:

```ruby
Todo.where(**filters).delete   # ArgumentError when filters is empty
Todo.all.update(done: false)   # every todo
```

A query with a join, `group`, `order`, `limit` or `offset`, or `into` a class with SQL expressions, can't be updated or deleted, because PostgreSQL and SQLite don't both support them there, so it raises an `ArgumentError` too, as does `update` with no columns.

### When the database says no

A duplicate email or a missing parent row is an outcome your code should handle, so the plain write methods return either their count or rows, or a `Skyward::ORM::Violation`:

```ruby
result = User.into(User).insert(email:)
case result
when User then created result
else result.kind == :unique ? conflict("That email is already registered") : unprocessable(result.message)
end
```

Steep 2.1 can't type-check `case`/`in`, so typed code matches on the class with `case`/`when`, and on the violation's `kind`.

`Skyward::ORM::Violation` has `kind` (`:unique`, `:foreign_key`, `:not_null` or `:check`), `constraint`, `columns` and the database's `message`.

Deleting a row that other rows still reference returns a `:foreign_key` violation when the reference's `on_delete` is `:restrict` or unset. Its `constraint` and `columns` describe the referencing table's foreign key, such as `todos_list_id_fkey` and `[:list_id]` when a `Todo` still references the `List`, because that's the constraint that failed.

When a violation would mean a bug, use the bang version: `insert!`, `insert_all!`, `update!` or `delete!`. It returns the same count or rows, or raises `Skyward::ORM::ViolationError`, which carries the violation, the way `save` and `save!` work in ActiveRecord:

```ruby
Todo.into(Todo).insert!(title: "Buy milk", list_id: 1)   # => Todo
Todo.where(id: 42).update!(done: true)                   # => Integer
Todo.where(done: true).into(Id).delete!                  # => Array[Id]
```

---

## Transactions

```ruby
Skyward.transaction do
  list = List.into(List).insert!(name: "Groceries")
  Todo.insert!(title: "Milk", list_id: list.id)
end
```

Every query inside the block runs in the transaction, and the block's value is returned. Skyward ORM rolls back if the block raises, **or if it returns a `Skyward::ORM::Violation`**, so the non-bang methods compose:

```ruby
result = Skyward.transaction do
  user = User.into(User).insert(email:)
  case user
  when User then Membership.insert(user_id: user.id, team_id:)
  else user # a violation: rolls back, then returns it
  end
end
```

A transaction belongs to the fiber that opened it. Ruby copies fiber storage into child fibers and threads, so a task started inside the block would otherwise share its connection. Skyward ORM raises if one tries to use it: "this transaction belongs to another fiber; start your own, or return the result to the block". `Skyward.transaction?` tells you whether you're inside one.

Each database has its own transactions, and no transaction spans two. Inside `Skyward.transaction`, a `Skyward.using(REPLICA)` block's queries run on the replica, outside the transaction, and `Skyward.transaction?` in the block is false unless it opens one of its own there.

---

## Types

Skyward ORM reads the same RBS as Steep, whether it's written inline or in `sig/`. It reads the `.rbs` files, and the CLI regenerates `sig/generated` from your inline types before it reads them, so you never run rbs-inline yourself. Here's what gets checked, and when:

| When                          | What's checked                                                                                                                                                                                                       |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **As you type (Steep)**       | The row type of every query. `Todo.where(...)` is a `Skyward::ORM::Query[Todo]`, `.to_a` is an `Array[Todo]`, `.into(TodoTitle)` is a `Projection[TodoTitle]`, `insert` and `insert_all` return `Integer \| Skyward::ORM::Violation`, `.into(Todo).insert` returns `Todo \| Skyward::ORM::Violation`, and `.into(Todo).insert_all` returns `Array[Todo] \| Skyward::ORM::Violation`. No annotations are needed. |
| **When you generate a migration** | Column types, nullability and enum values all come from your types.                                                                                                                                              |
| **At connect**                | Every table class against the live schema, which catches migrations you haven't run.                                                                                                                                 |
| **When a query is built**     | Column names exist, and values match their column's type. `where(dnoe: false)` and `where(done: "yes")` both raise immediately, so your first test run catches them.                                                 |
| **In the database**           | Constraints, which come back as `Skyward::ORM::Violation` values.                                                                                                                                                          |

Types are what Skyward ORM generates migrations from. Leave them off and queries still work, rows still come back as instances of your class, holding whatever values the driver returns, and you write the SQL for those columns yourself.

### How types map

| RBS                                     | PostgreSQL                                | Also compatible on PostgreSQL | SQLite              |
| --------------------------------------- | ----------------------------------------- | ----------------------------- | ------------------- |
| `Integer`                               | `bigint`                                  | `integer`, `smallint`         | `INTEGER`           |
| `int32`                                 | `integer`                                 |                               | `INTEGER`           |
| `int16`                                 | `smallint`                                |                               | `INTEGER`           |
| `Float`                                 | `double precision`                        | `real`                        | `REAL`              |
| `BigDecimal`                            | `numeric`                                 | `numeric(p,s)`                | `TEXT`              |
| `String`                                | `text`                                    | `varchar`, `uuid`, `citext`   | `TEXT`              |
| `uuid`                                  | `uuid`                                    |                               | `TEXT`              |
| `bool`                                  | `boolean`                                 |                               | `INTEGER` (0/1)     |
| `Date`                                  | `date`                                    |                               | `TEXT` (ISO 8601)   |
| `Time`                                  | `timestamptz`                             | `timestamp`                   | `TEXT` (ISO 8601)   |
| `:low \| :high`                         | `text` with a check, read back as Symbols | `varchar`                     | `TEXT` with a check |
| `T?`                                    | a nullable column                         |                               | a nullable column   |
| `Hash[String, untyped]`                 | `jsonb`                                   | `json`                        | `TEXT` (JSON)       |
| `Array[T]`                              | `T[]`                                     | a compatible `T`, with `[]`   | `TEXT` (JSON)       |

The PostgreSQL and SQLite columns are the types a generated migration writes. Edit a column in one to a compatible type and Skyward ORM keeps it: `Skyward.connect` accepts it, and `skyward migration` leaves it as it is. On PostgreSQL, that's a type in the compatible column, with any length or precision, and on SQLite any type with the same affinity, such as `bigint` or `varchar(255)`. `bool`, `Date` and `Time` are also compatible with `BOOLEAN`, `DATE` and `DATETIME`, the names Rails writes, which SQLite gives `NUMERIC` affinity. Only these three, because `NUMERIC` turns text that looks like a number into one, so `"1.10"` in a `String` column would come back as `1.1`. A boolean is already a number, and a date or time is never a well-formed number. A value a compatible type can't hold, such as `"nope"` for a `uuid` column typed `String`, raises the database's error, where typing it `uuid` raises an `ArgumentError` before any SQL runs. These mappings match Skyward API's, so a `Todo` read from the database and a `Todo` sent as JSON are the same thing.

A `Hash[String, untyped]` column holds JSON, for settings, metadata or a webhook's payload:

```ruby
# @dynamic settings, payload
attr_reader :settings  #: Hash[String, untyped]
attr_reader :payload   #: Hash[String, untyped]?
```

Its value is a Hash with String keys, whose values are `nil`, `true`, `false`, an Integer, a finite Float, a String, an Array of these or such a Hash, at every level, so the row reads back `==` to the one written. Anything else, such as a Symbol key or value, a `Time`, a `Date`, a `BigDecimal`, `NaN` or `Infinity`, would read back as something else, so a write refuses it with an `ArgumentError` naming where it is: `Webhook.payload is Hash[String, untyped]?, not :pending (Symbol) at payload["status"]`. A row holds the Hash frozen, and everything in it. `jsonb` doesn't keep the order of an object's keys, which a Hash's `==` ignores. Only `Hash[String, untyped]` is a column type: any other `Hash[String, T]` raises `Skyward::Core::BootError` saying to use it, since its values would need checking and reading by type inside the JSON.

A `BigDecimal` column holds an exact decimal, for a price or a measurement a `Float` would round:

```ruby
# @dynamic price, discount
attr_reader :price     #: BigDecimal
attr_reader :discount  #: BigDecimal?
```

Its value is a `BigDecimal` or an Integer, which is exact too and is written as the `BigDecimal` it is, so `2` and `BigDecimal("2")` are both `2.0`. A `Float` is refused, since `0.1` is already inexact before it reaches the column, and so is `NaN`, which never equals itself, each with an `ArgumentError` before any SQL runs: `Product.price is BigDecimal, not 0.1 (Float)`. `Infinity` is stored as it is. A row reads it back as a `BigDecimal`, with every digit. SQLite stores it as `TEXT`, because a `NUMERIC` or `DECIMAL(10,2)` column would store `1.10` as the `REAL` `1.1` and lose every digit past the 15th, so only a type with TEXT affinity is compatible there. `=` and `IN` compare that text, which is exact, since Skyward ORM always writes a value the same way, without an exponent. As text, `"10.5"` sorts before `"9.0"`, so on SQLite a range in `where` and `order` compare `CAST(price AS REAL)`, which is exact to 15 significant digits. PostgreSQL compares `numeric` as it is. It rounds a value to a hand-edited `numeric(10,2)` column's scale, or raises `numeric field overflow`, and the row holds what it stored. On SQLite, text other SQL wrote, such as `'1.50'`, doesn't equal the `1.5` Skyward ORM binds, while the rows Skyward ORM writes always match. A default, such as `default price: BigDecimal("1.5")`, is written unquoted, as `1.5`, as both databases read it back. On SQLite, a default is stored through a `REAL`, so one with more than 15 significant digits keeps only 15, and a stored `Infinity` or `-Infinity` compares and sorts as 0 in a range or `order`.

An `Array[T]` column holds a list, such as a todo's tags, its reminders or the weekdays it repeats on, without a join table:

```ruby
# @dynamic tags, reminders, weekdays
attr_reader :tags       #: Array[String]
attr_reader :reminders  #: Array[Time]?
attr_reader :weekdays   #: Array[:mon | :tue | :wed | :thu | :fri]
```

`T` is `Integer`, `Float`, `BigDecimal`, `String`, `bool`, `Date`, `Time` or a union of symbols, and the column may be nullable. PostgreSQL stores it as an array of `T`'s type, as `bigint[]`, `double precision[]`, `numeric[]`, `text[]`, `boolean[]`, `date[]` or `timestamptz[]`, and a union of symbols as `text[]`, with no check on its items, and takes an array of any type compatible with `T`, such as `integer[]` or `varchar(20)[]`. Each item keeps its type, so `where("? = ANY(tags)", "milk")` finds a row by one bound value. SQLite stores it as a JSON array in `TEXT`, each item as it stores `T`: a number as a number, `true` and `false` as JSON's, a `Date` as `YYYY-MM-DD`, a `Time` as UTC text to the microsecond, a `BigDecimal` as its digits in a string, and a Symbol as its name. Its value is an Array whose every item `T` takes, as a column of `T` that isn't nullable would, so a write refuses a `nil` item, a Symbol outside the union, and `Infinity` or `NaN` in an `Array[Float]`, which SQLite's JSON can't hold, though a `Float` column can, each with an `ArgumentError` naming the first item that doesn't fit: `Todo.tags is Array[String], not 3 (Integer) at tags[1]`. A row holds the Array frozen, and each item in it. `Array[T?]`, an Array of Arrays, and an Array of a Hash, a record, a class or `untyped` raise `Skyward::Core::BootError` saying what an item can be, and an Array of `uuid`, `int32` or `int16` saying it isn't a column type yet. A default, such as `default tags: []`, is written as the database stores the Array, `'{}'` on PostgreSQL and `'[]'` on SQLite.

---

## Testing

Test against a real database. In-memory SQLite or a local PostgreSQL is fast enough, and it's the only way to know your SQL works.

```ruby
# test/test_helper.rb
Skyward.connect(ENV.fetch("TEST_DATABASE_URL"), check: false)
Skyward.migrate("db/migrate") # runs any migration the test database hasn't had, then checks the schema
```

```ruby
describe Todo do
  include Skyward::ORM::Transactional # each test runs in a transaction that's rolled back afterwards

  let(:list) { List.into(List).insert!(name: "Home") }

  describe ".overdue" do
    it "skips todos that are done" do
      late = Todo.into(Todo).insert!(title: "Milk", list_id: list.id, due_on: Date.new(2026, 10, 1))
      Todo.insert!(title: "Eggs", list_id: list.id, due_on: Date.new(2026, 10, 1), done: true)

      assert_equal [late], Todo.overdue(today: Date.new(2026, 10, 18)).to_a
    end
  end
end
```

Rows are values, so assertions compare them directly with `==`.

`Skyward::ORM::Transactional` opens the transaction before setup and rolls it back after teardown, whether the test passed, failed or raised, so the rows `let` and `before` write go with it. A `Skyward.transaction` in the test is a savepoint, so a violation it returns rolls back only its own writes, and the test can still assert on what came before. `Skyward.transaction?` is false in the test itself and true only inside a `Skyward.transaction`, so code that branches on it behaves as it does in production.

The test's transaction belongs to the test's fiber. A thread or fiber the test starts that queries raises `FiberError`, as it would inside a `Skyward.transaction` in production, so return its result to the test instead.

When a test switches to another database with `Skyward.using`, `Skyward::ORM::Transactional` holds a transaction on that one too, the first time it does, and rolls it back with the rest. Each database is its own connection, so the second doesn't see rows the test wrote to the first and hasn't committed. A test environment with only one database can make the replica the database `Skyward.connect` kept, so `Skyward.using` changes nothing.

---

## Performance

- **Rows are values.** Skyward ORM has no identity map, dirty tracking, callbacks or per-row bookkeeping. Each row is one frozen object and its values.
- **Decoding is compiled.** Skyward ORM compiles a decoder for each table class that turns database values straight into rows, with no per-row hash in between.
- **SQL is cached by shape.** `where(id: 1)` and `where(id: 2)` share one SQL string and one prepared statement. Building a query is a cache lookup plus binding values.
- **Pooled connections, safe across threads and fibers.** The pool works under Puma or Falcon.
- **No hidden queries.** Skyward ORM has no lazy loading, so every query is one you wrote.

---

## CLI

Skyward ORM and Skyward API share one `skyward` command. Each adds its own commands to it. The executable comes with Skyward Core, which every Skyward gem depends on. The ORM's commands live in `lib/skyward/orm/commands.rb`, which registers each with `Skyward::Core::CLI.register`.

| Command                               | Does                                                                          |
| ------------------------------------- | ----------------------------------------------------------------------------- |
| `skyward migration add_notes_to_todos` | compares your table classes with the database and writes the migration        |
| `skyward migration --empty backfill`   | writes an empty migration for SQL you write yourself                          |
| `skyward migrate`                      | runs pending migrations                                                       |
| `skyward rollback`                     | runs the `-- down` section of the latest migration                            |
| `skyward status`                       | lists migrations, and any differences between your classes and the database, and exits 1 if anything needs doing |
| `skyward scaffold todos`               | prints a table class for an existing table, for adopting a database Skyward ORM didn't create |

The CLI runs in your app's directory and requires its `boot.rb`, which loads your table classes and calls `Skyward.connect`. First it regenerates `sig/generated` from your inline types, when rbs-inline is in your bundle, so it compares the types your Ruby has now. The migration commands turn the schema check off before they require it, because they're what fixes a mismatch. `skyward migration --empty` compares nothing, so it skips `boot.rb` and works before your app can connect.

`skyward scaffold todos > app/todo.rb` prints a whole file for one table, to save where your app keeps its classes: `# rbs_inline: enabled`, then a class named after the table, made singular (`todos` is `Todo`, `categories` is `Category`), with its declarations and an `attr_reader` for each column. Each type is the one [How types map](#how-types-map) gives the column's SQL type, so the class passes `Skyward.connect`'s check, and `skyward migration` finds nothing to write but what a comment in the class says it will. It doesn't guess from names or data: on SQLite an `INTEGER` column is an `Integer` and a `TEXT` one a `String`, though a migration stores `bool`, `Date` and `Time` in those too, unless it's declared `BOOLEAN`, `DATE` or `DATETIME`, and a column named `created_at` isn't taken to be a `Time`. A column no type maps to, such as `jsonb`, is `untyped`, and what a class can't declare, such as a check on two columns or an index on an expression, is a comment below `table`, since `skyward migration` will drop it. A default SQLite keeps as a literal that no Ruby value writes back the same, such as `1.50` or `TRUE`, is the value the column's type reads it as, `1.5` or `true`, with a comment saying `skyward migration` will rewrite it once, as that value, and one no value of the column's type reads as written, such as `'x'` or `'5'` on an `INTEGER` column, is listed with what it will drop. It refuses a table without a one-column primary key, and one a class already declares.

---

## Coming from other libraries

- **ActiveRecord.** `Todo.where` works the way you expect, and `insert`/`insert!` work like `save`/`save!`. A row is data, with no lifecycle: it has no callbacks, validations or associations. The columns are written in the class, where you can see them, and the migrations are written from them.
- **Sequel.** Queries are values here too. The rows are instances of your own typed classes, not hashes or models.
- **Django or Prisma.** The same declare-then-generate approach to migrations, in plain Ruby with RBS types.
- **Raw SQL.** Use it whenever you like (`Skyward.query`), and keep typed results and bound parameters.

---

## Design principles

1. **A class is a table, and its rows are values.** You query the class, and you get back frozen instances of it that you can use anywhere.
2. **The class is the schema.** Columns, types and constraints are declared once, in Ruby, where Steep and Skyward ORM can both read them. Migrations follow from them.
3. **A query is a value.** It's immutable, composable and printable, and nothing runs until you ask for rows.
4. **SQL stays in view.** Skyward ORM builds the SQL you'd write yourself, writes migrations as SQL you can read, and lets you write your own when that's clearer.
5. **Outcomes are values.** When the database says no, you get a `Skyward::ORM::Violation` to match on with `case`/`when`.
6. **No hidden work.** Skyward ORM has no lazy loading and no callbacks. Every query is one you can see.

---

## Status

This README is the spec, and this section lists each part of it that's built, as it lands. Anything it describes that isn't listed here isn't built yet.

- **Tables.** A table class subclasses `Skyward::ORM::Record`, and each `attr_reader` adds a column, in order. Skyward ORM registers its signatures with Skyward Core, so an app's signatures can subclass `Skyward::ORM::Record` too. `table`, `primary_key` (`:id` by default), `references` (with an optional `on_delete:` of `:cascade`, `:restrict`, `:set_null`, `:set_default` or `:no_action`), `default`, `unique`, `check` and `index` build one frozen schema for the class, and `Skyward.sql("...")` wraps an SQL expression for `default` and `check`. A malformed declaration raises `ArgumentError` in the class body: a column declared twice, a table or column name that isn't a Symbol, `unique` or `index` with no columns, `references` to anything but a table class or with another `on_delete:`, `Skyward.sql` given anything but a String, and a `check` given a plain String, both SQL and `length:`, neither, or a `length:` that isn't a Range of Integers, has no bound or is empty. A declaration can come before the `attr_reader` it names, so the columns declarations name, the default primary key included, are checked by a validation function that connecting and generating a migration call, which raises `Skyward::Core::BootError` naming the class and each column it doesn't have. Each declaration keeps its caller's file and line, from `caller_locations`, for each name it gives, beside the schema rather than in it, since the schema is compared as a value. So each column a declaration names that the class doesn't have gets its own excerpt of the declaration's line, with carets under the column's Symbol, or a `default`'s key, and `Did you mean ...?` with the closest of the class's columns when one is close. The default primary key is declared nowhere, and a class from `Class.new` or eval'd code keeps no lines, so they get neither. A class with no `table` raises `Skyward::Core::BootError` when its table name is asked for, saying to add `table :name`, with an excerpt of its `class` line, from `Object.const_source_location`, carets under its name.
- **Rows.** `Todo.new(**columns)` builds a frozen row, and raises `ArgumentError` naming the columns left out and the ones the class doesn't have. A row has `to_h`, `with`, `deconstruct_keys`, `==`, `eql?`, `hash` and `inspect` (`#<Todo id=1, title="Buy milk", done=false>`), and two rows are `==`, or `eql?`, when they're of the same class and each of their columns is. A table class's `members` are its columns, as a `Data` class's are its members. Each `attr_reader` compiles the class's row methods for its columns so far, so building and comparing a row reads and writes its columns directly, and redefining them never makes Ruby warn.
- **Column types.** Each column's type is read from the class's RBS through Skyward Core's reader, once per class for the signatures it loaded: `Integer`, `Float`, `BigDecimal`, `String`, `bool`, `Date`, `Time`, a union of symbols, keeping its symbols, `uuid`, `int32` and `int16`, `Hash[String, untyped]`, and `Array[T]` of `Integer`, `Float`, `BigDecimal`, `String`, `bool`, `Date`, `Time` or a union of symbols, an `Array` column keeping its element's type, and a union's symbols, with `T?` or `T | nil` nullable and aliases expanded. `uuid`, `int32` and `int16` are aliases of `String`, `Integer` and `Integer` that Skyward ORM declares in `Skyward::ORM`, and gives Skyward Core's reader as refinements, so each is its own column type, reached directly or through an app's alias of it. A column with no type or typed `untyped`, and every column of a class with no signature, is untyped, so its values will pass through as the driver returns them. A column typed as a record, a class or an `Array` of `uuid`, `int32` or `int16` raises `Skyward::Core::BootError` saying it isn't a column type yet, a `Hash[String, T]` of anything but `untyped` saying it isn't a column type and that a Hash column is `Hash[String, untyped]`, `Array[T?]`, an Array of Arrays, and an Array of a Hash, a record, a class or `untyped` saying it isn't a column type and what an Array column's items can be, any other type, such as a literal or a union of other types, saying it isn't a column type, and a type Skyward Core can't read with Skyward Core's explanation, each naming the column (`Todo#tags`). A table class's column adds an excerpt of its `attr_reader` line, with carets under the type in its `#:` comment, or under the column's name when its type is in a hand-written `.rbs`, and the reader's suggestion for a misspelt class name (`Did you mean String?`). A row class's members are read the same way, whether it's a table class or not.
- **Connecting.** `Skyward.connect(url, signatures: "sig", pool: 5, check:, default: true, instrument: nil)` loads the signatures under `signatures`, `sig/` in the current directory by default, connects through the adapter the URL's scheme picks, reads the database's schema, and keeps the database for every query, returning it. With `default: false` it returns the `Skyward::ORM::Database` without keeping it, so the one kept before stays, and each database has its own pool, column types and schema. It pools up to `pool:` connections, opening each only when it's needed. A query outside a transaction checks one out for the current fiber and returns it when done, and when every one is in use it waits for one to come back, blocking only its own fiber, and after 5 seconds raises `Skyward::ORM::PoolTimeout`, saying how long it waited for how many and to pass a larger `pool:`. A connection that comes back with a transaction still open, or on PostgreSQL in any state but idle, is rolled back and reused. One that still isn't idle, or whose rollback fails, is closed, and the pool opens another in its place when one is next needed, keeping the place for the next checkout if that open fails. Nothing a failed rollback or close raises reaches the code that returned the connection. A scheme with no adapter raises `Skyward::Core::BootError` naming the schemes Skyward ORM connects to, and the closest of them when one is close (`Did you mean postgres://?` for `postgress://`), without showing the URL. Everything that differs between databases sits behind an adapter: its name, opening a connection, how many it can pool, placeholders and how many values one statement binds, the `LIMIT` an `OFFSET` needs before it, the SQL type for each column type and which declared types are compatible with it, the clause that numbers an integer primary key, whether `ALTER TABLE` can change a column or constraint in place, how a default's SQL expression is written, encoding and decoding values, reading the schema (each table's columns with their declared type, nullability and default as a migration writes it, or a generated column's expression, its indexes with their `CREATE INDEX`, and its constraints with their names, columns and definitions as table constraints), turning a driver error into a `Skyward::ORM::Violation`, and beginning and ending a migration's transaction with its lock and finding the rows a migration left referring to missing ones. A row decoder is built once for each table class, row class and set of members given expressions, and cached: it reads each member by the row class's own RBS type, else by its table's column of that name, with `nil` as `nil`, every string frozen, a `Hash[String, untyped]` member's JSON read with `JSON.parse(value, freeze: true)`, frozen at every level, and an `Array[T]` member read item by item by `T`, frozen with each item, and passes through a member given an expression, or one its table has no column for, that the row class doesn't type.
- **Checking the schema.** `Skyward.connect` checks every loaded table class, each subclass of `Skyward::ORM::Record` at any depth that declares a `table`, in order of name. It validates each class's declarations, then compares its columns with the schema it read: a missing table, a missing column, a typed column whose declared type isn't compatible with its column type, and one whose nullability differs from its column's, raise `Skyward::ORM::SchemaMismatch`, a `Skyward::Core::BootError`. Its message has a block for each class that doesn't match, naming the class and its table, then a line for each problem, aligned on the column's name, and the fix below it. A missing table suggests the closest of the database's tables, and a missing column the closest of the table's columns the class doesn't declare (`todos has no column titel. Did you mean title?`), so a column added with no migration yet isn't pointed at another. A mismatch has no excerpt. An untyped column is only checked for presence, and the database's other columns, its indexes and its constraints are ignored. A generated column is checked as any other. A table class loaded after connect is checked before it's first queried or written on each database, by `count`, `exists?` or when its first row decoder there is built, which every write builds before it runs: once for each class that matches, under a lock so threads check it once, and again each time for one that doesn't. Raw SQL names no table class, so `Skyward.query` isn't checked. `check: false` skips both. Without `check:`, it checks unless the process's session has the check off: `Skyward::ORM::Connection::SESSION.without_check { ... }` turns it off for its block, and `skyward migration`, `skyward migrate`, `skyward rollback` and `skyward status` require `boot.rb` inside it, so they can write, run, undo and report the migration a mismatch needs. `Skyward.migrate` checks every loaded table class once it has migrated, and `skyward migrate` every one `skyward migration` finds, against the schema read again after migrating.
- **Switching databases.** `Skyward.using(database) { ... }` makes `database` the current one for its block and returns the block's value, so every query, write, `Skyward.transaction`, `Skyward.transaction?`, `Skyward.query` and `Skyward.migrate` in it uses it, each finding the current database when it runs rather than when it's built. The previous one is current again when the block ends, by returning, raising, `throw` or `break`, an inner `Skyward.using` switches again for its own block, and switching to the current database changes nothing. The switch is held in fiber storage, so a fiber or thread already running keeps its own database, and the fibers and threads the block starts inherit it. Anything but a `Skyward::ORM::Database` raises `ArgumentError` naming its class, without showing it, and so does no block.
- **Instrumenting.** `Skyward.connect(url, instrument: hook)` wraps every connection its pool opens in one that calls the hook around each statement it sends, `execute`, `execute2` and `execute_batch` alike, with a frozen `Skyward::ORM::Execution` of frozen copies of the statement's `sql` and its `binds` as the adapter encoded them, and the `adapter`'s name, `:postgresql` or `:sqlite`, before the statement is sent. The statement runs when the hook calls its block, which returns how many milliseconds the driver's call took, as a Float, and raises the driver's exception when the statement fails, which Skyward ORM then handles as it does without a hook, so a refused constraint still comes back as a `Skyward::ORM::Violation`. The hook's return value is ignored, and an exception it raises, before or after its block, raises out of the statement. A hook that never calls its block raises a `RuntimeError` saying it must call its block once, without running the statement, and so does a second call of the block, which runs nothing. So every statement a pooled connection sends is reported, in order: queries, writes, `Skyward.query`, transactions and savepoints, `Skyward::ORM::Transactional`'s `BEGIN` and `ROLLBACK`, the pool's `ROLLBACK` of a connection returned mid-transaction, migrations and their bookkeeping, and the schema reads at connect and after migrating, but not the session setup that opens a connection. A migration on PostgreSQL sends nothing to end it, since its lock ends with its transaction, so no statement is empty. The hook runs on the statement's fiber. Without `instrument:` the pool's connections are the adapter's own, and anything without `call` raises `Skyward::Core::BootError` naming its class before `Skyward.connect` connects.
- **Transactions.** `Skyward.transaction { ... }` checks a connection out and holds it for the whole block. It runs `BEGIN`, then commits and returns the block's value, or rolls back if the block raises (raising it again) or returns a `Skyward::ORM::Violation` (returning it). A block left any other way, such as by `throw`, rolls back, and so does a commit that fails, and a `BEGIN` or savepoint that an exception interrupts once it has reached the database, so the connection always goes back to the pool with no transaction open. When rolling back an interrupted `BEGIN` or savepoint fails, as it does when the start never reached the database, the exception that interrupted it is raised rather than the rollback's failure. On PostgreSQL, a savepoint's failed rollback leaves the enclosing transaction aborted until it rolls back too, so a block that rescues that exception and carries on gets PostgreSQL's "current transaction is aborted". A nested `Skyward.transaction` is a savepoint on the same connection, named by its depth, which rolls back only its own writes. The transaction belongs to the fiber that opened it: a child fiber or thread that inherits it through fiber storage and runs a query raises `FiberError`, "this transaction belongs to another fiber; start your own, or return the result to the block", and one that calls `Skyward.transaction` starts its own, on a connection of its own. `Skyward.transaction?` is true inside the block on the fiber that opened it, and false anywhere else. Each database's transactions are its own: inside one, a `Skyward.using` block's queries run on its database outside it, `Skyward.transaction?` there is that database's, and a `Skyward.transaction` there opens one on it.
- **Testing.** A Minitest test class or `describe` block that includes `Skyward::ORM::Transactional` runs each test in a transaction. Its `before_setup` checks a connection out, holds it for the test's fiber and runs `BEGIN`, and its `after_teardown` rolls back and returns the connection to the pool, whether the test passed, failed or raised, and even when another `after_teardown` raises, so rows from `let` and `before` are rolled back too and the next test starts from a clean database. A `Skyward.transaction` in the test is a savepoint on that connection, `Skyward.transaction?` is true only inside one, and a thread or fiber the test starts that queries raises `FiberError`, as it would inside a `Skyward.transaction` in production. The first time the test's fiber switches to another database with `Skyward.using`, it holds a transaction on that one too, and `after_teardown` rolls back each, even when one's rollback raises. A fiber or thread the test starts holds nothing on a database it switches to. It uses Minitest's hooks without requiring Minitest, which stays out of the gemspec.
- **SQLite.** `sqlite://path` and `sqlite://:memory:` connect with the `sqlite3` gem, which is in the app's Gemfile rather than Skyward ORM's gemspec: the adapter requires it on connect, and without it raises `Skyward::Core::BootError` saying to add `gem "sqlite3"`. It needs SQLite 3.35 or later, for `RETURNING`, and turns foreign keys on. Each connection to `:memory:` opens its own empty database, so it pools one connection whatever `pool:` says, and a connection to a file waits up to 5 seconds on another's lock rather than failing at once, letting other threads and fibers run while it waits. Its types, and the types compatible with them, are as [How types map](#how-types-map) says. A `Time` is stored as fixed-width UTC text to the microsecond, so text order is time order and it reads back `==` to the one written once truncated to microseconds. A `BigDecimal` is stored as its text, written with `to_s("F")`, which has no exponent, and read back as a `BigDecimal` with every digit, and a range or `order` on its column compares `CAST(column AS REAL)`. A `Hash[String, untyped]` column holds its JSON as text, with no check that it's JSON, since the ORM writes only JSON and PostgreSQL's `jsonb` needs none. An `Array[T]` column holds a JSON array as text, compatible with a declared type of TEXT affinity, each item as SQLite stores `T` but a `bool`, which is JSON's `true` or `false`, and an Integer in an `Array[Float]` reads back as a Float. SQLite takes an `OFFSET` only after a `LIMIT`, so an offset with no limit follows `LIMIT -1`. Constraint names, and their definitions, are read from each table's `CREATE TABLE`: a column's own constraint as the table constraint it's the same as, such as `FOREIGN KEY (list_id) REFERENCES lists`. SQLite reads a default back without the parentheses an expression was written in, so the adapter puts them back on anything but a literal. Columns are read with `pragma_table_xinfo`, which lists generated columns, stored or virtual, but not a virtual table's hidden ones, and a generated column's expression is read from the `CREATE TABLE`.
- **PostgreSQL.** `postgres://` and `postgresql://` URLs connect with the `pg` gem, which is in the app's Gemfile rather than Skyward ORM's gemspec: the adapter requires it on connect, and without it raises `Skyward::Core::BootError` saying to add `gem "pg"`. Its placeholders are `$1`, `$2` and so on, and it pools as many connections as `pool:` says. Each session runs with `TimeZone` set to UTC and `DateStyle` to ISO, whatever the server's defaults, and with `client_min_messages` at `warning`, since libpq prints every notice the server sends. Its types, and the types compatible with them, are the PostgreSQL columns of [How types map](#how-types-map). A `Time` is written in UTC to the microsecond, as PostgreSQL writes one back, and reads back `==` to the one written once truncated to microseconds, from a `timestamp` column as well as a `timestamptz`, a `date` reads back as a `Date`, a `boolean` as `true` or `false`, a `numeric` as a `BigDecimal`, sent as its `to_s("F")` text, a symbol union's column as Symbols, a `jsonb` or `json` column as a Hash, and an array column as a frozen Array. An `Array[T]` column takes an array, `T[]`, of any type compatible with `T`, and is bound as the text `PG::TextEncoder::Array` writes, which quotes each item that needs it, the string `NULL` included, from each item as the adapter sends it, a `bool` as `t` or `f`, and read with `PG::TextDecoder::Array`, each item by `T`. The driver returns every value as text, so an untyped column's value, and each value in a hash `Skyward.query` returns, is a String. The schema is read from `pg_catalog`: the tables an unqualified name finds, each column's type, nullability and default, or a generated column's expression in place of its default, the default as a migration writes it, without the cast PostgreSQL reads a literal back with (`'normal'` for `'normal'::text`, `'{}'` for `'{}'::text[]`, `-1` for `'-1'::integer`), each index but those its constraints make, with its `CREATE INDEX` as PostgreSQL writes it, and each primary key, unique, foreign key and check constraint by name, with its columns and its definition as PostgreSQL writes it. A migration alters its tables in place, and numbers an `Integer`, `int32` or `int16` primary key `GENERATED ALWAYS AS IDENTITY`, so an insert that gives that key a value is refused, as SQLite's `INTEGER PRIMARY KEY` isn't.
- **Violations.** `Skyward::ORM::Violation` has `kind` (`:unique`, `:foreign_key`, `:not_null` or `:check`), `constraint`, `columns` and the database's `message`. On SQLite the extended result code gives the kind, and the schema read at connect fills in the rest: a unique violation's constraint or unique index from the columns SQLite names, a check's columns from its name, and a foreign key's name and columns from the one foreign key the table written has or that refers to it. Raw SQL doesn't say which table it writes, so its check is looked for in every table, and its foreign key is the one any table has. SQLite doesn't say which foreign key failed, so when there's more than one the violation has neither. A not-null violation names its column and no constraint, and a check with no name has its expression as its constraint and no columns. On PostgreSQL the SQLSTATE gives the kind (`23505` unique, `23503` foreign key, `23502` not null, `23514` check), the constraint is the one the error names, its columns are that constraint's or unique index's in the schema read at connect, or a not-null violation's column, and the message is the server's.
- **Raw SQL.** `Skyward.query(RowClass, sql, *values)` runs the SQL on the current fiber's connection, inside its transaction if there is one, and returns an `Array` of the row class, which Steep reads as `Array[RowClass]`, and `Skyward.query(sql, *values)` returns an `Array` of symbol-keyed hashes. Each `?` outside a string, a quoted name or a comment becomes the adapter's placeholder, bound to its value as the adapter stores it, and a count of `?` that doesn't match the values, or a value that's an Array or a Hash, raises `ArgumentError`. A row class's members are its `members`, as a `Data` class, a `Struct` or a table class has, or else its keyword parameters. They're matched to the result's columns by name, so a result column with no member, or a member with no result column, raises `ArgumentError` naming it, even when no rows come back. Each member is read by its RBS type, so a SQLite date comes back a `Date`, with `nil` as `nil` and an untyped member passed through frozen, while a hash holds each value as the driver returns it. A constraint the SQL breaks raises `Skyward::ORM::ViolationError`, which carries the `Skyward::ORM::Violation` and its message, and any other error raises as it is.
- **Keeping types current.** `skyward migration`, but for `--empty`, `skyward migrate`, `skyward rollback`, `skyward status` and `skyward scaffold` regenerate `sig/generated` before they require `boot.rb`, with `Skyward::Core::Signatures::Inline.generate` and the rbs-inline in the bundle `skyward` runs in, so they read the types the Ruby has now. Without rbs-inline in the bundle, they use `sig/generated` as it is, and say nothing about it. When rbs-inline fails, they exit 1 with its output, without requiring `boot.rb`. With no `boot.rb`, they regenerate nothing.
- **Generating migrations.** `skyward migration NAME` requires `boot.rb` from the current directory with the schema check off, eager-loads every Zeitwerk loader, and finds every class below `Skyward::ORM::Record`, however deep, that declares a `table`. It checks each class's declarations name its columns, refuses two classes that declare one table, with an excerpt of each one's `table` line, and compares each with the schema read at connect. A table the database doesn't have is created, after the new tables it references, and then each table that differs from its class is changed to match it. A table with no class is left alone. It writes them to `db/migrate/<UTC timestamp>_NAME.sql`, with a `-- down` section that undoes each change in reverse order, and prints what it found, as [Migrations](#migrations) shows. Each column has the adapter's type, `NOT NULL` unless it's nullable, its default (a `Skyward.sql` expression in parentheses on SQLite, a `Hash[String, untyped]` column's Hash as its JSON, an `Array[T]` column's Array as the database stores it, quoted, and a `BigDecimal` column's value unquoted, an Integer as a decimal, as both databases read it back), a one-column `unique`, its checks, its symbol union's check and its reference, and multi-column uniques and indexes follow. An `Integer`, `int32` or `int16` primary key is the adapter's identity column, SQLite's `INTEGER PRIMARY KEY`, and any other, such as a `uuid`, takes its `default`. Every constraint and index is named after its table, columns and kind: `todos_pkey`, `todos_list_id_fkey`, `todos_email_key`, `todos_title_check` (`todos_title_check1` for a column's second), and `todos_list_id_done_index`. A column with no type gets `-- TODO: todos.notes needs a type` in place of its definition, and an added required column with no default gets `-- TODO: todos.notes needs a DEFAULT for the rows todos already has`. A name that isn't letters, digits and `_`, or more than one, shows the usage, and a name a migration already has, or a migration in `db/migrate` whose version isn't in `schema_migrations`, stops it, so running it twice can't write the same change twice. When every table matches its class it says so and writes nothing. Each refusal, and a `Skyward::Core::BootError` from booting or from a class, exits 1 with only its message. A changed table gets, in this order: its indexes and constraints the class doesn't declare, but could, dropped, then its columns the class doesn't have, then its column and constraint renames, its new columns, each column whose type isn't compatible, whose default differs (a `DEFAULT NULL` is no default, as PostgreSQL keeps it, and a `Hash[String, untyped]` or `Array[T]` column's default, a string literal, is compared by the value the column reads from it, since PostgreSQL respells `jsonb`, reading `'{"a":1}'` back as `'{"a": 1}'`, and a float in an array, reading `'{1.0e+20}'` back as `'{1e+20}'`) or whose `NULL` does, and then the constraints and indexes the class declares that it doesn't have. A column that went is asked about each new column of a compatible type, in order, "Did you rename todos.notes to todos.details? [y/N]", until one is a yes (`y` or `yes`, in any case), and a column it's renamed to isn't asked about again. Without a terminal it exits 1, writing nothing, with "skyward: did you rename todos.notes to todos.details? There's no terminal to ask, so nothing was written. Run `skyward migration` in a terminal to answer.", naming every rename it would have asked about. An untyped column's type and `NULL` aren't compared. A generated column's default isn't compared, and one the class doesn't declare is never dropped or asked about as a rename. A constraint is matched by its name, or, with no name, as SQLite can have, by its kind and columns, and a unique or reference also by its columns, the table it references and what it does `ON DELETE`. A unique or reference the class declares that the table has under another name, matched by all of those, is renamed to the class's name, and when the table has two, the first is renamed and the other dropped. A check is matched by its name alone, since PostgreSQL rewrites its expression, so a check whose rule changes keeps its name and isn't noticed: write that migration with `--empty`. An index is matched by its columns, so one under another name is kept. What a class can't declare is left alone, neither dropped nor added: an index whose `CREATE INDEX` is unique or has an expression, a `WHERE`, a method other than `btree` or an `INCLUDE`, a check on no column or on more than one that has no name the class declares, and a foreign key on more than one column or whose `REFERENCES` names columns other than its table's primary key. A new column's own constraints are part of its `ADD COLUMN`. On PostgreSQL, each change is an `ALTER TABLE`: `DROP INDEX` and `CREATE INDEX`, `ADD`/`DROP CONSTRAINT` and `RENAME CONSTRAINT old TO new` by name, `DROP`/`RENAME`/`ADD COLUMN`, and `ALTER COLUMN` with `TYPE ... USING col::type`, `SET`/`DROP DEFAULT` and `SET`/`DROP NOT NULL`, each undone by its opposite in reverse order. SQLite does in place only what its `ALTER TABLE` can: add a column that isn't a key and whose default isn't an expression, drop or rename one, and drop or create an index. Anything else rebuilds the table, as [Migrations](#migrations) says, keeping the type an untyped column has, each constraint the class can't declare, as a table constraint, and each index it can't, from its `CREATE INDEX`, and the down section rebuilds it as it was read, with its constraints as table constraints and its indexes' own `CREATE INDEX`. A table with a generated column isn't rebuilt, since the rebuild would lose the column: `skyward migration` raises `Skyward::Core::BootError`, writing nothing, with a line for each such table naming it and its generated columns and saying to write the migration with `skyward migration --empty`. A dropped column comes back in the down section with `-- todos.notes comes back empty: dropping it lost its data`, and a `DEFAULT` TODO when it's required with none, and a column made `NOT NULL` gets `-- TODO: backfill the NULLs in todos.due_on before it becomes NOT NULL`. PostgreSQL's migrations are written with its adapter's types and DDL, and run in the tests on a real PostgreSQL.
- **Empty migrations.** `skyward migration --empty NAME`, with `--empty` before or after the name, writes `db/migrate/<UTC timestamp>_NAME.sql` holding an empty up section and a `-- down` line, for SQL you write yourself, and prints its path. Its file name sorts among generated ones, so it'll run in order with them. It takes a name by the same rules, refuses a name a migration already has, and shows the usage given any other flag. It compares nothing, so it doesn't require `boot.rb` and works before the app can connect, and a migration that hasn't run doesn't stop it.
- **Running migrations.** `Skyward.migrate(directory)` runs each pending `.sql` file in the directory on the current database, in filename order, and returns the versions it ran. Only the part before a `-- down` line runs. `schema_migrations`, created if it's missing, records each version with a SHA-256 checksum of its up section, line endings normalised, and when it ran. Each migration runs on one connection in its own transaction with its version's row, which first takes a lock one migrator holds at a time and then checks again that the version hasn't run, so two deploys migrating at once run each file once, and a crashed one can't leave the lock behind. On SQLite it turns foreign keys off and checks them before committing, as [Migrations](#migrations) describes, and a migration that leaves a row referring to a missing one rolls back, naming each. SQLite's lock is `BEGIN IMMEDIATE`, and PostgreSQL's is `pg_advisory_xact_lock`, which a second migrator waits on until the first commits, and then sees what it ran. On PostgreSQL foreign keys are checked as each statement writes. A migration that fails rolls back, nothing after it runs, and `Skyward::ORM::MigrationError` names the file with the database's message. So does a migration that can't take the lock, which on SQLite means waiting more than 5 seconds, and on PostgreSQL only a `lock_timeout` the server or session sets, and its connection is left with no transaction open. Before running anything, it raises `Skyward::ORM::MigrationError` naming each migration whose up section changed after it ran. Changing a `-- down` section is fine, and a migration that ran but whose file is gone doesn't stop the rest, so old migrations can be squashed. Once it has migrated, even with nothing pending, it reads the schema again on the same connection and checks the table classes against it, raising `Skyward::ORM::SchemaMismatch` for one that doesn't match. `skyward migrate` requires `boot.rb` from the current directory with the schema check off, as `skyward migration` does, runs `db/migrate`, prints `Migrated <version>` for each or `No pending migrations.`, and then checks. A failed or refused migration, a mismatch, and a `Skyward::Core::BootError` from booting, exits 1 with only its message.
- **Rolling back.** `skyward rollback` requires `boot.rb` with the schema check off, as `skyward migrate` does, and undoes the latest migration, the greatest version in `schema_migrations`, one migration a run. It takes the same lock in its own transaction, checks again that the version is still the latest, runs the migration's `-- down` section, with foreign keys off and checked before it commits on SQLite, and checked as each statement writes on PostgreSQL, and deletes its row, then prints `Rolled back <version>`. It rolls back nothing, and exits 1 with only its reason, when no migration has run, when the latest one's file is gone, when its `-- down` section is blank, when it can't take the lock, or when another migrator ran or rolled back a migration while it waited for the lock. A `-- down` section that fails is undone, and it names the file with the database's message. It reads the schema again afterwards, as migrating does.
- **Migration status.** `skyward status` requires `boot.rb` with the schema check off, and lists each migration in `db/migrate` in order, as ran, pending, or edited after it ran (its up section's checksum differs), with each version that ran but whose file is gone among them. Then it shows how each table class `skyward migration` finds differs from the database, as `skyward migration` summarises it, except that a column that may have been renamed shows as one dropped and one added, since it doesn't ask. Then, under each table, it names each index and constraint the table keeps that its class can't declare, as "kept: not declared by Todo", and then each table no class declares, other than `schema_migrations`, saying to run `skyward scaffold TABLE` for one. When there's nothing to report, it says so. It only reads, so it doesn't create `schema_migrations`. It exits 1 when a migration is pending, edited or gone, a class differs from its table, or a table has no class, but not for what a table keeps, so CI can gate on it, and with only its message for a `Skyward::Core::BootError`.
- **Scaffolding.** `skyward scaffold TABLE` boots as `skyward status` does, finds the app's table classes as `skyward migration` does, and prints a table class for the table to stdout, reading only. It takes exactly one table, and shows the usage given none, more than one, or a flag. It exits 1 with only its message, printing nothing, for a table the database doesn't have, suggesting one that's close ("skyward: there's no table todo. Did you mean todos?"), for `schema_migrations`, for a table a loaded class declares, for one with no primary key or one on more than one column, and for a column that isn't a lowercase Ruby method name or is one a row already has (`to_h`, `hash`, `with`, `members` and the like). The file starts with `# rbs_inline: enabled`, and `# @rbs use Skyward::ORM::*` when a column is a `uuid`, `int32` or `int16`. The class is the table's name camel-cased with a trailing `s` dropped (`ies` becomes `y`, `sses` becomes `ss`, and `ss` stays), and declares, in order: `table`, `primary_key` for a key other than `id`, `references`, `default`, `unique`, `check` and `index`, then a `# @dynamic` line and an `attr_reader` for each column in the table's order, its `#:` comment aligned. Each adapter's `column_type` reads a column's SQL type back as the narrowest column type `compatible?` accepts for it: on PostgreSQL `bigint`, `integer` and `smallint` as `Integer`, `int32` and `int16`, `double precision` and `real` as `Float`, `numeric` as `BigDecimal`, `text`, `character varying` and `citext` as `String`, `uuid` as `uuid`, `boolean` as `bool`, `jsonb` and `json` as `Hash[String, untyped]`, `date` as `Date` and either `timestamp` as `Time`, with any length or precision, and on SQLite `BOOLEAN`, `DATE` and `DATETIME` as `bool`, `Date` and `Time`, and any other type by its affinity, `INTEGER` as `Integer`, `REAL` as `Float` and `TEXT` as `String`. A `text` or `varchar` column with a check that lists only strings, as SQLite keeps `IN (...)` and PostgreSQL rewrites it as `= ANY (ARRAY[...])`, is a symbol union, and the check is left to the type. A nullable column is `T?`, and a nullable union `(:a | :b)?`. Any other column is `untyped`, with a comment above it naming its SQL type, or saying it has none. A default the column's type reads as a literal written back the same, such as `0`, `1.5`, `"x"`, `false`, `:normal`, `Date.new(2026, 1, 1)` or, on SQLite, `Time.utc(2026, 1, 2, 3, 4, 5)`, is that value, and any other is `Skyward.sql(...)` holding it as the catalog reads it, without the parentheses SQLite's adapter puts back. SQLite keeps a literal as it was written, even in parentheses, so one that no value writes back the same, such as `1.50`, `TRUE`, `010` or `'2026-01-02 03:04:05'`, is instead the value the column's type reads it as (`1.5`, `true`, `10`, `Time.utc(2026, 1, 2, 3, 4, 5)`), and a comment above `default` names its column as one `skyward migration` will rewrite once, as that value. One no value of the column's type reads as written, such as `'x'` or `'5'` on an `INTEGER` column, `0` on a `TEXT` one or `'2026-02-30 03:04:05'` on a `DATETIME` one, even where SQLite converts it, is left out of `default` and listed below `table` as its column and default (`count DEFAULT 'x'`), with what `skyward migration` will drop. A one-column foreign key to the referenced table's primary key is `references`, with `on_delete:` from its `ON DELETE` unless that's `NO ACTION`, naming the loaded class that declares the referenced table, or else the class `skyward scaffold` would print for it, with a comment above saying to scaffold that table too. A unique constraint is `unique`, and so is a unique btree index on columns alone, with a comment that `skyward migration` will replace the index with a constraint. A check on one column is `check :column, Skyward.sql(...)`, holding what's inside its `CHECK (...)`, and a btree index on columns alone is `index`. A foreign key on more than one column or to another column, a check on more than one column or none, and an index on an expression, with a `WHERE`, or by another method, are listed below `table`, each with its definition, under a comment saying `skyward migration` will drop them. Every line of a comment that holds a definition, name or type the database keeps starts with `#`, so one that spans several lines stays a comment.
- **Reading.** `Todo.all` is a query of every row on the current database, and `Todo.join`, `Todo.left_join`, `Todo.where`, `Todo.exclude`, `Todo.order` and `Todo.find_by` start from it, so Steep types each as a `Skyward::ORM::Query[Todo]` with no annotations. `Todo.into` starts a `Skyward::ORM::Projection` of every row that, unlike `Todo.all`, can't update or delete every row. A query is frozen, and `join`, `left_join`, `where`, `exclude`, `or`, `order`, `group`, `limit` and `offset` each return a new one. `where(column: value)` is `=`, `nil` is `IS NULL` and an array is `IN`: an empty array matches nothing without emitting `IN ()`, and an array holding `nil` matches `IS NULL` too. A range compares with its ends, `>=` its beginning and `<=` its end, or `<` an excluded end, leaving out an end it doesn't have, and a range with neither end raises `ArgumentError`. `where("sql", *values)` adds the SQL in parentheses, each `?` in it becoming the adapter's placeholder, numbered on from the query's other values, while a `?` inside a quoted string, a quoted name or a comment is left as it is. A count of `?` that doesn't match the values, or an `Array` or `Hash` value, which the driver would spread across several placeholders, raises `ArgumentError` when the query runs or shows its SQL. `exclude` takes what `where` takes and adds `NOT (...)`, keeping the `NULL` rows of a nullable or untyped column, which SQL's `NOT` would leave out, with `OR column IS NULL`, unless the condition matches `NULL` itself: an SQL string's columns can't be known, so it's a plain `NOT`. `or` takes what `where` takes too, and joins it to everything before it, so `where(a).where(b).or(c).where(d)` is `((a AND b) OR c) AND d`, and on a query with no conditions, or given nothing, it raises `ArgumentError`, while an `exclude` given nothing keeps the query's conditions but no longer counts as an explicit `Todo.all`. Repeated `where`s and `exclude`s are joined with `AND`, and `order(:title, created_at: :desc)` and `group` append to what's there. A column the table doesn't have raises `ArgumentError` as the query is built, with a "did you mean" suggestion when one is close, and so does an order direction other than `:asc` or `:desc`. Each value given to `where`, `exclude`, `or` or `find_by` as a hash condition is checked against its column's type from the cached column types as the query is built, and one the type doesn't take raises `ArgumentError` naming the class, column, declared type and value: `Todo.done is bool, not "yes" (String)`. `Integer` takes Integers, `int32` and `int16` Integers in their range, `Float` Integers and Floats but `NaN`, which SQLite stores as `NULL`, `BigDecimal` BigDecimals and Integers but `NaN`, which never equals itself, `String` Strings, `uuid` Strings of 8-4-4-4-12 hex digits, in either case, `bool` `true` and `false`, `Date` Dates but not DateTimes, `Time` Times, and a union of symbols only its own Symbols, while `nil` passes only for a nullable column. A `Hash[String, untyped]` column is matched only to `nil`, which is `IS NULL`, and any other value, a Range included, raises `ArgumentError` saying to match its contents with an SQL string, since PostgreSQL compares `jsonb` by value and SQLite compares the JSON's text. So is an `Array[T]` column, where an Array, an empty one included, would otherwise mean `IN`. Each element of an array is checked, and so is each end of a range, with an open end left unchecked. An Integer for a `BigDecimal` column, in a condition or a write, is bound as the `BigDecimal` it is, so `2` is `2.0`, as SQLite's text comparison needs. An untyped column takes any value but a Hash, or an Array inside the array or at an end of a range, since the driver would spread either across several placeholders. `insert` and `update` check their values against the same types, each as one value, so an Array or a Range is refused rather than unpacked, but for an `Array[T]` column's Array. `limit(n)` and `offset(n)` take a non-negative Integer, raising `ArgumentError` for anything else as the query is built, and a later call replaces the earlier value. Both are bound as parameters, so every page of a query shares one SQL string. `first` runs with `LIMIT 1` in place of the query's limit, keeping its offset, ordered by the primary key when nothing else orders it, so both databases return the same row, and returns a row or `nil`. `find_by(**conditions)` is `where(...).first`. `count` runs `COUNT(*)` without the query's order, and counts the groups of a grouped query, and the rows a limited or offset query's page holds, through a subquery. `exists?` runs `SELECT 1` with `LIMIT 1`, keeping the offset but not the order, and returns `true` or `false`, `false` for a limit of 0. `each` and every `Enumerable` method run the query once per call, and `each` without a block returns an `Enumerator`. `to_sql` returns the SQL and the encoded values it binds, in the connected adapter's placeholder style, without running anything. Every table and column name is quoted, with an embedded double quote doubled, so a column named `order`, `group` or `user` can be queried. Rows are decoded with the cached decoder. `into(RowClass, **expressions)` returns a `Skyward::ORM::Projection[RowClass]`, a query whose writes return rows, with every other clause kept, every clause after it keeps it one, and calling it again replaces the projection. The row class's members are found as `Skyward.query` finds them. A member with no expression selects the table's column of that name, and one with an expression selects it as `expr AS "member"`, written into the SQL as given. A member that's neither a column nor given an expression, and an expression for a name that isn't a member, raise `ArgumentError` as the query is built. `where`, `exclude`, `or`, `order` and `group` still name the table's columns, and the values of `where`, `exclude` and `or` are still checked against those columns' types. `join(List, list_id: :id)` adds `JOIN "lists" ON "todos"."list_id" = "lists"."id"`, and `left_join` takes the same and adds `LEFT JOIN`: each key names a column of the starting table and its value a column of the joined one, and more than one pair is joined with `AND`. A class that isn't a table class, a table already in the query, since aliases aren't supported, no pairs, and a column either table doesn't have, with a "did you mean" suggestion, raise `ArgumentError` as the query is built. Once a query has a join, every column it names itself is qualified with its table: each member it selects without an expression, and the columns of `where`, `exclude`, `or`, `order`, `group` and `first`'s primary key, which all mean the starting table's. A joined table's columns are read through an expression, such as `list_name: "lists.name"`, and matched with an SQL string, such as `where("lists.archived = ?", false)`. Without `into`, a joined query returns rows of the starting table, one for each row it matches, and a member filled from a `left_join` is `nil` when no row matches. `count`, `exists?` and running the query check each table class it joins, as they check the one it starts from. `merge(other)` takes a `Skyward::ORM::Query` of the same table class and returns a new query, as if each of `other`'s clauses had been called after the query's own, so Steep types it as the query it's called on: a `Projection` stays one, with its row class and expressions. `other`'s conditions follow with `AND`, and a side holding an `or` is parenthesised, so `where(a).merge(where(b).or(c))` is `a AND (b OR c)`, `where(a).or(b).merge(where(c))` is `(a OR b) AND c`, and a later `or` joins to everything before it. Placeholders are numbered as the merged query renders, so an SQL string on either side binds its values in order. `other`'s `order` and `group` append, its `limit` and `offset` replace the query's when it has them, and its joins are added after the query's, with a join identical to one the query has (same table, kind and columns) kept once, and every column qualified once the merged query has a join. The merged query is narrowed when either was, and is an explicit `Todo.all`, which may update or delete every row, only when both were. A query of a different table class, naming both, a `Projection`, a different join of a table already in the query, and anything that isn't a query raise `ArgumentError` as the query is built. Caching SQL by shape is still to come.
- **Writing.** `Todo.insert(**values)` inserts a row and returns how many rows it inserted, 1, or a `Skyward::ORM::Violation`, so Steep types it as `Integer | Skyward::ORM::Violation` with no annotations, and given no values it inserts `DEFAULT VALUES`. A column the class doesn't have, or a required one left out (one that isn't nullable, has no `default` and isn't the primary key), raises `ArgumentError` naming it before any SQL runs, as does a value its column's type doesn't take. An Array or a Range is never one value, for any column but an `Array[T]` one, so a write refuses it rather than unpacking it as `where` does. A Hash for a `Hash[String, untyped]` column is one value, bound to one placeholder as `JSON.generate` writes it, once each value in it is checked: its keys must be Strings, and its values `nil`, `true`, `false`, Integers, finite Floats, Strings, and Arrays and Hashes of these, at every level. The first that isn't raises `ArgumentError` naming the column, its type, the value and where it is, as `Webhook.payload is Hash[String, untyped]?, not :pending (Symbol) at payload["status"]`, or `as a key of payload` for a key. Only the column says to encode a Hash, so a Hash bound to a `?` in SQL, or written to an untyped column, is still refused. An Array for an `Array[T]` column is one value, bound to one placeholder as the adapter writes an array, once each item is checked as a value for a column of `T` that isn't nullable: the first that isn't raises `ArgumentError` naming the column, its type, the item and its index, as `Todo.tags is Array[String], not 3 (Integer) at tags[1]`, so a `nil` item is refused, and so is `Infinity` or `NaN` in an `Array[Float]`. An Integer in an `Array[BigDecimal]` is written as the `BigDecimal` it is. Only the column says an Array is one value, so an Array bound to a `?` in SQL, or written to any other column, is still refused. A column with no type, like one the class doesn't declare, is left to the database. A column the schema read at connect says is generated isn't required, and a write given it raises `ArgumentError` naming it before any SQL runs. `update(**values)` on a query sets the values on the rows it matches and returns how many it changed, or a violation, checking each value's type the same way, and raises `ArgumentError` given no values. `delete` on a query deletes the rows it matches and returns how many it deleted, or a violation, usually a foreign key whose `on_delete` is `:restrict` or unset, whose `constraint` and `columns` are the referencing table's foreign key, since that's the one that failed. Each write is one statement with no `RETURNING`, and its count is the one the driver gives for it, which leaves out rows a cascade changed. On a `Skyward::ORM::Projection`, from `into(RowClass)` anywhere before the write, each write returns rows of the row class instead, through `RETURNING` of just its members' columns, or every column for the table class itself: `insert(**values)` its one row, and `update` and `delete` an `Array`, so Steep types them as `RowClass | Skyward::ORM::Violation` and `Array[RowClass] | Skyward::ORM::Violation`. `insert` on a projection raises `ArgumentError` before any SQL runs, naming each clause, unless the query has nothing but `into`: conditions, even from a `where` or `exclude` given nothing, `into` expressions, a `join` or `left_join`, `order`, `group`, `limit` or `offset`. Each write checks its table class against the schema, as a query does, and runs inside the fiber's transaction if there is one. `update` and `delete` raise `ArgumentError` on a query `into` a class with expressions, or with a `join` or `left_join`, `order`, `group`, `limit` or `offset`, which PostgreSQL and SQLite don't both support there, and on one with no conditions from `where`, `exclude` or `or`, which would change every row, unless it's an explicit `Todo.all` that no `where` or `exclude` has narrowed, even one given nothing, so `Todo.all.into(Id).delete` deletes every row while `Todo.into(Id).delete` raises. `Todo.insert_all(rows)` inserts an `Array` of symbol-keyed hashes in one `INSERT ... VALUES (...), (...)` with no `RETURNING`, and returns the driver's count of the rows it inserted, or a violation, which inserts none of them and doesn't say which row broke it, so Steep types it as `Integer | Skyward::ORM::Violation`, and on a projection, which takes nothing but `into` as `insert` does, it returns the rows through `RETURNING`, in no promised order, typed `Array[RowClass] | Skyward::ORM::Violation`. The first row's keys are the statement's columns, in its order, and a row whose keys differ, in any order, raises `ArgumentError` naming its index and the columns it has that the first row doesn't, and those it lacks. Each row is checked as `insert` checks one, before any SQL runs, each message naming its index: `Todo.insert_all row 3: Todo.done is bool, not "yes" (String)`, and a required column left out names the method and row, as `Todo.insert_all row 3 needs title`, where `insert` says `Todo.insert needs title`. A first row with no columns raises `ArgumentError` saying to use `insert` for a row of defaults, since neither database takes `DEFAULT VALUES` for more than one row, and so do more rows times columns than the adapter's limit on bound values, 65535 on PostgreSQL, the protocol's, and 32766 on SQLite, its default since 3.32, naming the limit and saying to split the rows, in a `Skyward.transaction` if they must land together. A SQLite built with a lower limit refuses with its own error, since the `sqlite3` gem can't read it. `insert_all([])` returns 0, or `[]` on a projection, without checking out a connection. `insert!`, `insert_all!`, `update!` and `delete!` return the same count or rows, or raise `Skyward::ORM::ViolationError`, which carries the violation and its message. A violation the plain methods return rolls back the `Skyward.transaction` block it's returned from.
