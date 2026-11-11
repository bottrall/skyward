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

Column types come from the `#:` comments, the same types Steep reads. `T?` means a nullable column, everything else is `NOT NULL`, and a symbol union such as `:low | :normal | :high` gets a check constraint for its values.

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
- **Migrations are plain SQL files you commit.** Read them, edit them, and add data backfills to the same file. Skyward ORM runs each one once, in order, inside a transaction. `skyward rollback` runs the `-- down` section.
- **Every change has a down.** A dropped column comes back in the down section with a comment that its data isn't restored, since dropping it lost that.
- **Skyward ORM asks when it can't know what you meant.** If a column disappears and another of a compatible type appears, it asks whether you renamed it, rather than dropping your data. Yes renames it, and no drops one and adds the other. With no terminal to ask, as in CI, it writes nothing, and names the columns to run it again for in a terminal.
- **Generation needs types.** A column without a `#:` type still works at runtime, but Skyward ORM can't guess its SQL type. The migration gets `-- TODO: todos.notes needs a type`, and you write that line yourself.
- **A new required column needs a default.** The rows already in the table need a value for it, so the migration gets `-- TODO: todos.notes needs a DEFAULT for the rows todos already has`. Give it one, or make the column nullable.
- **A column made required needs its `NULL`s filled.** The migration gets `-- TODO: backfill the NULLs in todos.due_on before it becomes NOT NULL`, where your `UPDATE` goes.
- **SQLite rebuilds a table to change it.** SQLite's `ALTER TABLE` adds, drops and renames columns, but can't change one or its constraints, so the migration creates the new table, copies the rows, drops the old table, renames the new one and recreates its indexes. Dropping a table runs the `ON DELETE` of every table that references it, and SQLite only turns foreign keys off outside a transaction, so `skyward migrate` and `skyward rollback` run each SQLite migration with `PRAGMA foreign_keys = OFF`, and check them with `PRAGMA foreign_key_check` before they commit. The rows that reference a rebuilt table stay as they were.
- **A table with no class is never dropped.** A class that isn't loaded looks the same as one that's gone, so `skyward status` reports the table instead.
- **Hand-written migrations are always an option.** `skyward migration --empty backfill_priorities` gives you an empty file for SQL you write yourself.

Business rules like the title length live in the database, where they hold for every writer, and they come back to Ruby as a [`Violation`](#when-the-database-says-no).

---

## Connecting

```ruby
Skyward.connect(ENV.fetch("DATABASE_URL"), pool: 10)
```

Call it once, where your app boots. Skyward ORM reads your column types from the `.rbs` files under `sig/`, or the directory you pass as `signatures:`.

Like ActiveRecord, Skyward ORM keeps the connection for you, so `Todo.where(...)` just works. It also gives you what makes that safe: tests that each run in a rolled-back transaction, and `Skyward.using(other_database) { ... }` to switch databases for one block. The switch applies only to the current fiber, never globally.

When you connect, Skyward ORM compares every loaded table class with the live schema and refuses to start if they disagree:

```
Skyward::ORM::SchemaMismatch: Todo doesn't match the todos table

  notes  todos has no column notes.
         Run `skyward migrate`, or `skyward migration` if you haven't generated one.
```

It looks for each table and column the class declares, and for a typed column, a compatible type and the same nullability. A column without a type only has to be there. Columns the class doesn't declare, indexes and constraints aren't compared, and `skyward status` lists those differences. A table class loaded after connect is checked the first time it's used.

`Skyward.connect(url, check: false)` skips the check, for what fixes a mismatch. The migration commands turn it off for their process before they boot your app, so the `Skyward.connect(url)` in your `boot.rb` needs no change, and `Skyward.migrate` runs the check once it has migrated.

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
| `where("title ILIKE ?", "%milk%")`       | `(title ILIKE '%milk%')`, with the value bound as a parameter |

A range with only one end compares with that end alone, and a range with neither end raises `ArgumentError`. An SQL string goes in parentheses, and each `?` in it binds the next value, numbered on from the query's other values in the connected database's placeholder style. A `?` inside a quoted string, a quoted name or a comment is the SQL's own and is left as it is. When the query runs or shows its SQL, a count of `?` that doesn't match the values raises `ArgumentError`, and so does an `Array` or `Hash` value, which the driver would spread across several placeholders.

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

### Seeing the SQL

Every query can show its SQL without running it:

```ruby
sql, binds = Todo.where(done: false, priority: [:high, :normal]).order(created_at: :desc).to_sql

puts sql
# SELECT "id", "list_id", "title", "priority", "due_on", "done", "created_at" FROM "todos"
# WHERE "done" = $1 AND "priority" IN ($2, $3) ORDER BY "created_at" DESC

binds # => [false, "high", "normal"]
```

Every table and column name is quoted, so a column named `order` or `user` works like any other. The placeholders and values are the ones the connected database is sent: on SQLite the placeholders are `?` and `false` is `0`.

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

`into` names the rows to return instead, through `RETURNING` of just its members' columns, or every column for the table class itself. It can come anywhere before the write. `insert` returns its one row, and `update` and `delete` return an `Array`:

```ruby
Id = Data.define(:id)

Todo.into(Todo).insert(title: "Buy milk", list_id: 1)   # => Todo, every column
Todo.into(Id).insert(title: "Buy milk", list_id: 1)     # => Id, RETURNING "id"
Todo.where(id: 42).into(Todo).update(done: true)        # => Array[Todo], the updated rows
Todo.where(done: true).into(Id).delete                  # => Array[Id], the deleted rows' ids
```

`insert` on a query takes nothing but `into`. Anything else on the query, such as a `where`, an `order` or a join, raises an `ArgumentError` before any SQL runs.

Columns with a default (`id`, `done`, `created_at`) and nullable ones (`due_on`) are optional. The rest are required, and leaving one out raises an `ArgumentError` straight away, as does a column the class doesn't have, a value its column's type doesn't take, or an Array or a Range, which is never one value. A column without a type is left to the database, and `insert` with no columns inserts a row of defaults.

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

When a violation would mean a bug, use the bang version: `insert!`, `update!` or `delete!`. It returns the same count or rows, or raises `Skyward::ORM::ViolationError`, which carries the violation, the way `save` and `save!` work in ActiveRecord:

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

---

## Types

Skyward ORM reads the same RBS as Steep, whether it's written inline or in `sig/`. It reads the `.rbs` files, and the CLI regenerates `sig/generated` from your inline types before it reads them, so you never run rbs-inline yourself. Here's what gets checked, and when:

| When                          | What's checked                                                                                                                                                                                                       |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **As you type (Steep)**       | The row type of every query. `Todo.where(...)` is a `Skyward::ORM::Query[Todo]`, `.to_a` is an `Array[Todo]`, `.into(TodoTitle)` is a `Projection[TodoTitle]`, `insert` returns `Integer \| Skyward::ORM::Violation`, and `.into(Todo).insert` returns `Todo \| Skyward::ORM::Violation`. No annotations are needed. |
| **When you generate a migration** | Column types, nullability and enum values all come from your types.                                                                                                                                              |
| **At connect**                | Every table class against the live schema, which catches migrations you haven't run.                                                                                                                                 |
| **When a query is built**     | Column names exist, and values match their column's type. `where(dnoe: false)` and `where(done: "yes")` both raise immediately, so your first test run catches them.                                                 |
| **In the database**           | Constraints, which come back as `Skyward::ORM::Violation` values.                                                                                                                                                          |

Types are what Skyward ORM generates migrations from. Leave them off and queries still work, rows still come back as instances of your class, holding whatever values the driver returns, and you write the SQL for those columns yourself.

### How types map

| RBS                     | PostgreSQL                                       | SQLite            |
| ----------------------- | ------------------------------------------------ | ----------------- |
| `Integer`               | `bigint`                                         | `INTEGER`         |
| `Float`                 | `double precision`                               | `REAL`            |
| `BigDecimal`            | `numeric`                                        | `TEXT`            |
| `String`                | `text`                                           | `TEXT`            |
| `bool`                  | `boolean`                                        | `INTEGER` (0/1)   |
| `Date`                  | `date`                                           | `TEXT` (ISO 8601) |
| `Time`                  | `timestamptz`                                    | `TEXT` (ISO 8601) |
| `:low \| :high`         | `text` with a check, read back as Symbols        | `TEXT` with a check |
| `T?`                    | a nullable column                                | a nullable column |
| `Hash[String, untyped]` | `jsonb`                                          | `TEXT` (JSON)     |
| `Array[T]`              | `T[]`                                            | `TEXT` (JSON)     |

This is the type in a generated migration. When reading an existing column, Skyward ORM also accepts compatible types, such as `integer` or `varchar`. These mappings match Skyward API's, so a `Todo` read from the database and a `Todo` sent as JSON are the same thing.

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

- **Tables.** A table class subclasses `Skyward::ORM::Record`, and each `attr_reader` adds a column, in order. Skyward ORM registers its signatures with Skyward Core, so an app's signatures can subclass `Skyward::ORM::Record` too. `table`, `primary_key` (`:id` by default), `references` (with an optional `on_delete:` of `:cascade`, `:restrict`, `:set_null`, `:set_default` or `:no_action`), `default`, `unique`, `check` and `index` build one frozen schema for the class, and `Skyward.sql("...")` wraps an SQL expression for `default` and `check`. A malformed declaration raises `ArgumentError` in the class body: a column declared twice, a table or column name that isn't a Symbol, `unique` or `index` with no columns, `references` to anything but a table class or with another `on_delete:`, `Skyward.sql` given anything but a String, and a `check` given a plain String, both SQL and `length:`, neither, or a `length:` that isn't a Range of Integers, has no bound or is empty. A declaration can come before the `attr_reader` it names, so the columns declarations name, the default primary key included, are checked by a validation function that connecting and generating a migration call, which raises `Skyward::Core::BootError` naming the class and each column it doesn't have. A class with no `table` raises `Skyward::Core::BootError` when its table name is asked for, saying to add `table :name`.
- **Rows.** `Todo.new(**columns)` builds a frozen row, and raises `ArgumentError` naming the columns left out and the ones the class doesn't have. A row has `to_h`, `with`, `deconstruct_keys`, `==`, `eql?`, `hash` and `inspect` (`#<Todo id=1, title="Buy milk", done=false>`), and two rows are `==`, or `eql?`, when they're of the same class and each of their columns is. A table class's `members` are its columns, as a `Data` class's are its members. Each `attr_reader` compiles the class's row methods for its columns so far, so building and comparing a row reads and writes its columns directly, and redefining them never makes Ruby warn.
- **Column types.** Each column's type is read from the class's RBS through Skyward Core's reader, once per class for the signatures it loaded: `Integer`, `Float`, `String`, `bool`, `Date`, `Time` and a union of symbols, keeping its symbols, with `T?` or `T | nil` nullable and aliases expanded. A column with no type or typed `untyped`, and every column of a class with no signature, is untyped, so its values will pass through as the driver returns them. A column typed as a record, a class, an `Array` or a `Hash` raises `Skyward::Core::BootError` saying it isn't a column type yet, any other type, such as a literal or a union of other types, saying it isn't a column type, and a type Skyward Core can't read with Skyward Core's explanation, each naming the column (`Todo#tags`). A row class's members are read the same way, whether it's a table class or not.
- **Connecting.** `Skyward.connect(url, signatures: "sig", pool: 5, check:)` loads the signatures under `signatures`, `sig/` in the current directory by default, connects through the adapter the URL's scheme picks, reads the database's schema, and keeps the database for every query, returning it. It pools up to `pool:` connections, opening each only when it's needed. A query outside a transaction checks one out for the current fiber and returns it when done, and when every one is in use it waits for one to come back, blocking only its own fiber, and after 5 seconds raises `Skyward::ORM::PoolTimeout`, saying how long it waited for how many and to pass a larger `pool:`. A connection that comes back with a transaction still open, or on PostgreSQL in any state but idle, is rolled back and reused. One that still isn't idle, or whose rollback fails, is closed, and the pool opens another in its place when one is next needed, keeping the place for the next checkout if that open fails. Nothing a failed rollback or close raises reaches the code that returned the connection. A scheme with no adapter raises `Skyward::Core::BootError` naming the schemes Skyward ORM connects to, without showing the URL. Everything that differs between databases sits behind an adapter: opening a connection, how many it can pool, placeholders, the `LIMIT` an `OFFSET` needs before it, the SQL type for each column type and which declared types are compatible with it, the clause that numbers an integer primary key, whether `ALTER TABLE` can change a column or constraint in place, how a default's SQL expression is written, encoding and decoding values, reading the schema (each table's columns with their declared type, nullability and default as a migration writes it, its indexes with their `CREATE INDEX`, and its constraints with their names, columns and definitions as table constraints), turning a driver error into a `Skyward::ORM::Violation`, and beginning and ending a migration's transaction with its lock and finding the rows a migration left referring to missing ones. A row decoder is built once for each table class, row class and set of members given expressions, and cached: it reads each member by the row class's own RBS type, else by its table's column of that name, with `nil` as `nil` and every string frozen, and passes through a member given an expression, or one its table has no column for, that the row class doesn't type.
- **Checking the schema.** `Skyward.connect` checks every loaded table class, each subclass of `Skyward::ORM::Record` at any depth that declares a `table`, in order of name. It validates each class's declarations, then compares its columns with the schema it read: a missing table, a missing column, a typed column whose declared type isn't compatible with its column type, and one whose nullability differs from its column's, raise `Skyward::ORM::SchemaMismatch`, a `Skyward::Core::BootError`. Its message has a block for each class that doesn't match, naming the class and its table, then a line for each problem, aligned on the column's name, and the fix below it. An untyped column is only checked for presence, and the database's other columns, its indexes and its constraints are ignored. A table class loaded after connect is checked before it's first queried or written, by `count`, `exists?` or when its first row decoder is built, which every write builds before it runs: once for each class that matches, under a lock so threads check it once, and again each time for one that doesn't. Raw SQL names no table class, so `Skyward.query` isn't checked. `check: false` skips both. Without `check:`, it checks unless the process's session has the check off: `Skyward::ORM::Connection::SESSION.without_check { ... }` turns it off for its block, and `skyward migration`, `skyward migrate`, `skyward rollback` and `skyward status` require `boot.rb` inside it, so they can write, run, undo and report the migration a mismatch needs. `Skyward.migrate` checks every loaded table class once it has migrated, and `skyward migrate` every one `skyward migration` finds, against the schema read again after migrating.
- **Transactions.** `Skyward.transaction { ... }` checks a connection out and holds it for the whole block. It runs `BEGIN`, then commits and returns the block's value, or rolls back if the block raises (raising it again) or returns a `Skyward::ORM::Violation` (returning it). A block left any other way, such as by `throw`, rolls back, and so does a commit that fails, and a `BEGIN` or savepoint that an exception interrupts once it has reached the database, so the connection always goes back to the pool with no transaction open. When rolling back an interrupted `BEGIN` or savepoint fails, as it does when the start never reached the database, the exception that interrupted it is raised rather than the rollback's failure. On PostgreSQL, a savepoint's failed rollback leaves the enclosing transaction aborted until it rolls back too, so a block that rescues that exception and carries on gets PostgreSQL's "current transaction is aborted". A nested `Skyward.transaction` is a savepoint on the same connection, named by its depth, which rolls back only its own writes. The transaction belongs to the fiber that opened it: a child fiber or thread that inherits it through fiber storage and runs a query raises `FiberError`, "this transaction belongs to another fiber; start your own, or return the result to the block", and one that calls `Skyward.transaction` starts its own, on a connection of its own. `Skyward.transaction?` is true inside the block on the fiber that opened it, and false anywhere else. `Skyward.using` is still to come.
- **Testing.** A Minitest test class or `describe` block that includes `Skyward::ORM::Transactional` runs each test in a transaction. Its `before_setup` checks a connection out, holds it for the test's fiber and runs `BEGIN`, and its `after_teardown` rolls back and returns the connection to the pool, whether the test passed, failed or raised, and even when another `after_teardown` raises, so rows from `let` and `before` are rolled back too and the next test starts from a clean database. A `Skyward.transaction` in the test is a savepoint on that connection, `Skyward.transaction?` is true only inside one, and a thread or fiber the test starts that queries raises `FiberError`, as it would inside a `Skyward.transaction` in production. It uses Minitest's hooks without requiring Minitest, which stays out of the gemspec.
- **SQLite.** `sqlite://path` and `sqlite://:memory:` connect with the `sqlite3` gem, which is in the app's Gemfile rather than Skyward ORM's gemspec: the adapter requires it on connect, and without it raises `Skyward::Core::BootError` saying to add `gem "sqlite3"`. It needs SQLite 3.35 or later, for `RETURNING`, and turns foreign keys on. Each connection to `:memory:` opens its own empty database, so it pools one connection whatever `pool:` says, and a connection to a file waits up to 5 seconds on another's lock rather than failing at once, letting other threads and fibers run while it waits. Its types are the SQLite column of [How types map](#how-types-map), and a declared type with the same SQLite affinity is compatible, such as `bigint` or `varchar(255)`. A `Time` is stored as fixed-width UTC text to the microsecond, so text order is time order and it reads back `==` to the one written once truncated to microseconds. SQLite takes an `OFFSET` only after a `LIMIT`, so an offset with no limit follows `LIMIT -1`. Constraint names, and their definitions, are read from each table's `CREATE TABLE`: a column's own constraint as the table constraint it's the same as, such as `FOREIGN KEY (list_id) REFERENCES lists`. SQLite reads a default back without the parentheses an expression was written in, so the adapter puts them back on anything but a literal.
- **PostgreSQL.** `postgres://` and `postgresql://` URLs connect with the `pg` gem, which is in the app's Gemfile rather than Skyward ORM's gemspec: the adapter requires it on connect, and without it raises `Skyward::Core::BootError` saying to add `gem "pg"`. Its placeholders are `$1`, `$2` and so on, and it pools as many connections as `pool:` says. Each session runs with `TimeZone` set to UTC and `DateStyle` to ISO, whatever the server's defaults, and with `client_min_messages` at `warning`, since libpq prints every notice the server sends. Its types are the PostgreSQL column of [How types map](#how-types-map), and `integer`, `smallint`, `varchar` and `timestamp`, with any length or precision, are compatible too. A `Time` is written in UTC to the microsecond, as PostgreSQL writes one back, and reads back `==` to the one written once truncated to microseconds, from a `timestamp` column as well as a `timestamptz`, a `date` reads back as a `Date`, a `boolean` as `true` or `false`, and a symbol union's column as Symbols. The driver returns every value as text, so an untyped column's value, and each value in a hash `Skyward.query` returns, is a String. The schema is read from `pg_catalog`: the tables an unqualified name finds, each column's type, nullability and default, as a migration writes it, without the cast PostgreSQL reads a literal back with (`'normal'` for `'normal'::text`, `-1` for `'-1'::integer`), each index but those its constraints make, with its `CREATE INDEX` as PostgreSQL writes it, and each primary key, unique, foreign key and check constraint by name, with its columns and its definition as PostgreSQL writes it. A migration alters its tables in place, and numbers an integer primary key `GENERATED ALWAYS AS IDENTITY`, so an insert that gives that key a value is refused, as SQLite's `INTEGER PRIMARY KEY` isn't.
- **Violations.** `Skyward::ORM::Violation` has `kind` (`:unique`, `:foreign_key`, `:not_null` or `:check`), `constraint`, `columns` and the database's `message`. On SQLite the extended result code gives the kind, and the schema read at connect fills in the rest: a unique violation's constraint or unique index from the columns SQLite names, a check's columns from its name, and a foreign key's name and columns from the one foreign key the table written has or that refers to it. Raw SQL doesn't say which table it writes, so its check is looked for in every table, and its foreign key is the one any table has. SQLite doesn't say which foreign key failed, so when there's more than one the violation has neither. A not-null violation names its column and no constraint, and a check with no name has its expression as its constraint and no columns. On PostgreSQL the SQLSTATE gives the kind (`23505` unique, `23503` foreign key, `23502` not null, `23514` check), the constraint is the one the error names, its columns are that constraint's or unique index's in the schema read at connect, or a not-null violation's column, and the message is the server's.
- **Raw SQL.** `Skyward.query(RowClass, sql, *values)` runs the SQL on the current fiber's connection, inside its transaction if there is one, and returns an `Array` of the row class, which Steep reads as `Array[RowClass]`, and `Skyward.query(sql, *values)` returns an `Array` of symbol-keyed hashes. Each `?` outside a string, a quoted name or a comment becomes the adapter's placeholder, bound to its value as the adapter stores it, and a count of `?` that doesn't match the values, or a value that's an Array or a Hash, raises `ArgumentError`. A row class's members are its `members`, as a `Data` class, a `Struct` or a table class has, or else its keyword parameters. They're matched to the result's columns by name, so a result column with no member, or a member with no result column, raises `ArgumentError` naming it, even when no rows come back. Each member is read by its RBS type, so a SQLite date comes back a `Date`, with `nil` as `nil` and an untyped member passed through frozen, while a hash holds each value as the driver returns it. A constraint the SQL breaks raises `Skyward::ORM::ViolationError`, which carries the `Skyward::ORM::Violation` and its message, and any other error raises as it is.
- **Keeping types current.** `skyward migration`, but for `--empty`, `skyward migrate`, `skyward rollback` and `skyward status` regenerate `sig/generated` before they require `boot.rb`, with `Skyward::Core::Signatures::Inline.generate` and the rbs-inline in the bundle `skyward` runs in, so they read the types the Ruby has now. Without rbs-inline in the bundle, they use `sig/generated` as it is, and say nothing about it. When rbs-inline fails, they exit 1 with its output, without requiring `boot.rb`. With no `boot.rb`, they regenerate nothing.
- **Generating migrations.** `skyward migration NAME` requires `boot.rb` from the current directory with the schema check off, eager-loads every Zeitwerk loader, and finds every class below `Skyward::ORM::Record`, however deep, that declares a `table`. It checks each class's declarations name its columns, refuses two classes that declare one table, and compares each with the schema read at connect. A table the database doesn't have is created, after the new tables it references, and then each table that differs from its class is changed to match it. A table with no class is left alone. It writes them to `db/migrate/<UTC timestamp>_NAME.sql`, with a `-- down` section that undoes each change in reverse order, and prints what it found, as [Migrations](#migrations) shows. Each column has the adapter's type, `NOT NULL` unless it's nullable, its default (a `Skyward.sql` expression in parentheses on SQLite), a one-column `unique`, its checks, its symbol union's check and its reference, and multi-column uniques and indexes follow. An integer primary key is the adapter's identity column, SQLite's `INTEGER PRIMARY KEY`. Every constraint and index is named after its table, columns and kind: `todos_pkey`, `todos_list_id_fkey`, `todos_email_key`, `todos_title_check` (`todos_title_check1` for a column's second), and `todos_list_id_done_index`. A column with no type gets `-- TODO: todos.notes needs a type` in place of its definition, and an added required column with no default gets `-- TODO: todos.notes needs a DEFAULT for the rows todos already has`. A name that isn't letters, digits and `_`, or more than one, shows the usage, and a name a migration already has, or a migration in `db/migrate` whose version isn't in `schema_migrations`, stops it, so running it twice can't write the same change twice. When every table matches its class it says so and writes nothing. Each refusal, and a `Skyward::Core::BootError` from booting or from a class, exits 1 with only its message. A changed table gets, in this order: its indexes and constraints the class doesn't declare dropped, then its columns the class doesn't have, then its renames, its new columns, each column whose type isn't compatible, whose default differs (a `DEFAULT NULL` is no default, as PostgreSQL keeps it) or whose `NULL` does, and then the constraints and indexes the class declares that it doesn't have. A column that went is asked about each new column of a compatible type, in order, "Did you rename todos.notes to todos.details? [y/N]", until one is a yes (`y` or `yes`, in any case), and a column it's renamed to isn't asked about again. Without a terminal it exits 1, writing nothing, with "skyward: did you rename todos.notes to todos.details? There's no terminal to ask, so nothing was written. Run `skyward migration` in a terminal to answer.", naming every rename it would have asked about. An untyped column's type and `NULL` aren't compared. A constraint is matched by its name, or, with no name, as SQLite can have, by its kind and columns, and a unique or reference also by its columns, the table it references and what it does `ON DELETE`. A check is matched by its name alone, since PostgreSQL rewrites its expression, so a check whose rule changes keeps its name and isn't noticed: write that migration with `--empty`. An index is matched by its columns, so one under another name is kept, and a unique index, which a class can't declare, is dropped. A new column's own constraints are part of its `ADD COLUMN`. On PostgreSQL, each change is an `ALTER TABLE`: `DROP INDEX` and `CREATE INDEX`, `ADD`/`DROP CONSTRAINT` by name, `DROP`/`RENAME`/`ADD COLUMN`, and `ALTER COLUMN` with `TYPE ... USING col::type`, `SET`/`DROP DEFAULT` and `SET`/`DROP NOT NULL`, each undone by its opposite in reverse order. SQLite does in place only what its `ALTER TABLE` can: add a column that isn't a key and whose default isn't an expression, drop or rename one, and drop or create an index. Anything else rebuilds the table, as [Migrations](#migrations) says, keeping the type an untyped column has, and the down section rebuilds it as it was read, with its constraints as table constraints and its indexes' own `CREATE INDEX`. A dropped column comes back in the down section with `-- todos.notes comes back empty: dropping it lost its data`, and a `DEFAULT` TODO when it's required with none, and a column made `NOT NULL` gets `-- TODO: backfill the NULLs in todos.due_on before it becomes NOT NULL`. PostgreSQL's migrations are written with its adapter's types and DDL, and run in the tests on a real PostgreSQL.
- **Empty migrations.** `skyward migration --empty NAME`, with `--empty` before or after the name, writes `db/migrate/<UTC timestamp>_NAME.sql` holding an empty up section and a `-- down` line, for SQL you write yourself, and prints its path. Its file name sorts among generated ones, so it'll run in order with them. It takes a name by the same rules, refuses a name a migration already has, and shows the usage given any other flag. It compares nothing, so it doesn't require `boot.rb` and works before the app can connect, and a migration that hasn't run doesn't stop it.
- **Running migrations.** `Skyward.migrate(directory)` runs each pending `.sql` file in the directory on the database `Skyward.connect` kept, in filename order, and returns the versions it ran. Only the part before a `-- down` line runs. `schema_migrations`, created if it's missing, records each version with a SHA-256 checksum of its up section, line endings normalised, and when it ran. Each migration runs on one connection in its own transaction with its version's row, which first takes a lock one migrator holds at a time and then checks again that the version hasn't run, so two deploys migrating at once run each file once, and a crashed one can't leave the lock behind. On SQLite it turns foreign keys off and checks them before committing, as [Migrations](#migrations) describes, and a migration that leaves a row referring to a missing one rolls back, naming each. SQLite's lock is `BEGIN IMMEDIATE`, and PostgreSQL's is `pg_advisory_xact_lock`, which a second migrator waits on until the first commits, and then sees what it ran. On PostgreSQL foreign keys are checked as each statement writes. A migration that fails rolls back, nothing after it runs, and `Skyward::ORM::MigrationError` names the file with the database's message. So does a migration that can't take the lock, which on SQLite means waiting more than 5 seconds, and on PostgreSQL only a `lock_timeout` the server or session sets, and its connection is left with no transaction open. Before running anything, it raises `Skyward::ORM::MigrationError` naming each migration whose up section changed after it ran. Changing a `-- down` section is fine, and a migration that ran but whose file is gone doesn't stop the rest, so old migrations can be squashed. Once it has migrated, even with nothing pending, it reads the schema again on the same connection and checks the table classes against it, raising `Skyward::ORM::SchemaMismatch` for one that doesn't match. `skyward migrate` requires `boot.rb` from the current directory with the schema check off, as `skyward migration` does, runs `db/migrate`, prints `Migrated <version>` for each or `No pending migrations.`, and then checks. A failed or refused migration, a mismatch, and a `Skyward::Core::BootError` from booting, exits 1 with only its message.
- **Rolling back.** `skyward rollback` requires `boot.rb` with the schema check off, as `skyward migrate` does, and undoes the latest migration, the greatest version in `schema_migrations`, one migration a run. It takes the same lock in its own transaction, checks again that the version is still the latest, runs the migration's `-- down` section, with foreign keys off and checked before it commits on SQLite, and checked as each statement writes on PostgreSQL, and deletes its row, then prints `Rolled back <version>`. It rolls back nothing, and exits 1 with only its reason, when no migration has run, when the latest one's file is gone, when its `-- down` section is blank, when it can't take the lock, or when another migrator ran or rolled back a migration while it waited for the lock. A `-- down` section that fails is undone, and it names the file with the database's message. It reads the schema again afterwards, as migrating does.
- **Migration status.** `skyward status` requires `boot.rb` with the schema check off, and lists each migration in `db/migrate` in order, as ran, pending, or edited after it ran (its up section's checksum differs), with each version that ran but whose file is gone among them. Then it shows how each table class `skyward migration` finds differs from the database, as `skyward migration` summarises it, except that a column that may have been renamed shows as one dropped and one added, since it doesn't ask, and then each table no class declares, other than `schema_migrations`. When there's nothing to report, it says so. It only reads, so it doesn't create `schema_migrations`. It exits 1 when a migration is pending, edited or gone, a class differs from its table, or a table has no class, so CI can gate on it, and with only its message for a `Skyward::Core::BootError`.
- **Reading.** `Todo.all` is a query of every row on the connected database, and `Todo.join`, `Todo.left_join`, `Todo.where`, `Todo.exclude`, `Todo.order` and `Todo.find_by` start from it, so Steep types each as a `Skyward::ORM::Query[Todo]` with no annotations. `Todo.into` starts a `Skyward::ORM::Projection` of every row that, unlike `Todo.all`, can't update or delete every row. A query is frozen, and `join`, `left_join`, `where`, `exclude`, `or`, `order`, `group`, `limit` and `offset` each return a new one. `where(column: value)` is `=`, `nil` is `IS NULL` and an array is `IN`: an empty array matches nothing without emitting `IN ()`, and an array holding `nil` matches `IS NULL` too. A range compares with its ends, `>=` its beginning and `<=` its end, or `<` an excluded end, leaving out an end it doesn't have, and a range with neither end raises `ArgumentError`. `where("sql", *values)` adds the SQL in parentheses, each `?` in it becoming the adapter's placeholder, numbered on from the query's other values, while a `?` inside a quoted string, a quoted name or a comment is left as it is. A count of `?` that doesn't match the values, or an `Array` or `Hash` value, which the driver would spread across several placeholders, raises `ArgumentError` when the query runs or shows its SQL. `exclude` takes what `where` takes and adds `NOT (...)`, keeping the `NULL` rows of a nullable or untyped column, which SQL's `NOT` would leave out, with `OR column IS NULL`, unless the condition matches `NULL` itself: an SQL string's columns can't be known, so it's a plain `NOT`. `or` takes what `where` takes too, and joins it to everything before it, so `where(a).where(b).or(c).where(d)` is `((a AND b) OR c) AND d`, and on a query with no conditions, or given nothing, it raises `ArgumentError`, while an `exclude` given nothing keeps the query's conditions but no longer counts as an explicit `Todo.all`. Repeated `where`s and `exclude`s are joined with `AND`, and `order(:title, created_at: :desc)` and `group` append to what's there. A column the table doesn't have raises `ArgumentError` as the query is built, with a "did you mean" suggestion when one is close, and so does an order direction other than `:asc` or `:desc`. Each value given to `where`, `exclude`, `or` or `find_by` as a hash condition is checked against its column's type from the cached column types as the query is built, and one the type doesn't take raises `ArgumentError` naming the class, column, declared type and value: `Todo.done is bool, not "yes" (String)`. `Integer` takes Integers, `Float` Floats and Integers, `String` Strings, `bool` `true` and `false`, `Date` Dates but not DateTimes, `Time` Times, and a union of symbols only its own Symbols, while `nil` passes only for a nullable column. Each element of an array is checked, and so is each end of a range, with an open end left unchecked. An untyped column takes any value but a Hash, or an Array inside the array or at an end of a range, since the driver would spread either across several placeholders. `insert` and `update` check their values against the same types, each as one value, so an Array or a Range is refused rather than unpacked. `limit(n)` and `offset(n)` take a non-negative Integer, raising `ArgumentError` for anything else as the query is built, and a later call replaces the earlier value. Both are bound as parameters, so every page of a query shares one SQL string. `first` runs with `LIMIT 1` in place of the query's limit, keeping its offset, ordered by the primary key when nothing else orders it, so both databases return the same row, and returns a row or `nil`. `find_by(**conditions)` is `where(...).first`. `count` runs `COUNT(*)` without the query's order, and counts the groups of a grouped query, and the rows a limited or offset query's page holds, through a subquery. `exists?` runs `SELECT 1` with `LIMIT 1`, keeping the offset but not the order, and returns `true` or `false`, `false` for a limit of 0. `each` and every `Enumerable` method run the query once per call, and `each` without a block returns an `Enumerator`. `to_sql` returns the SQL and the encoded values it binds, in the connected adapter's placeholder style, without running anything. Every table and column name is quoted, with an embedded double quote doubled, so a column named `order`, `group` or `user` can be queried. Rows are decoded with the cached decoder. `into(RowClass, **expressions)` returns a `Skyward::ORM::Projection[RowClass]`, a query whose writes return rows, with every other clause kept, every clause after it keeps it one, and calling it again replaces the projection. The row class's members are found as `Skyward.query` finds them. A member with no expression selects the table's column of that name, and one with an expression selects it as `expr AS "member"`, written into the SQL as given. A member that's neither a column nor given an expression, and an expression for a name that isn't a member, raise `ArgumentError` as the query is built. `where`, `exclude`, `or`, `order` and `group` still name the table's columns, and the values of `where`, `exclude` and `or` are still checked against those columns' types. `join(List, list_id: :id)` adds `JOIN "lists" ON "todos"."list_id" = "lists"."id"`, and `left_join` takes the same and adds `LEFT JOIN`: each key names a column of the starting table and its value a column of the joined one, and more than one pair is joined with `AND`. A class that isn't a table class, a table already in the query, since aliases aren't supported, no pairs, and a column either table doesn't have, with a "did you mean" suggestion, raise `ArgumentError` as the query is built. Once a query has a join, every column it names itself is qualified with its table: each member it selects without an expression, and the columns of `where`, `exclude`, `or`, `order`, `group` and `first`'s primary key, which all mean the starting table's. A joined table's columns are read through an expression, such as `list_name: "lists.name"`, and matched with an SQL string, such as `where("lists.archived = ?", false)`. Without `into`, a joined query returns rows of the starting table, one for each row it matches, and a member filled from a `left_join` is `nil` when no row matches. `count`, `exists?` and running the query check each table class it joins, as they check the one it starts from. `merge` and caching SQL by shape are still to come.
- **Writing.** `Todo.insert(**values)` inserts a row and returns how many rows it inserted, 1, or a `Skyward::ORM::Violation`, so Steep types it as `Integer | Skyward::ORM::Violation` with no annotations, and given no values it inserts `DEFAULT VALUES`. A column the class doesn't have, or a required one left out (one that isn't nullable, has no `default` and isn't the primary key), raises `ArgumentError` naming it before any SQL runs, as does a value its column's type doesn't take. An Array or a Range is never one value, for any column, so a write refuses it rather than unpacking it as `where` does. A column with no type, like one the class doesn't declare, is left to the database. `update(**values)` on a query sets the values on the rows it matches and returns how many it changed, or a violation, checking each value's type the same way, and raises `ArgumentError` given no values. `delete` on a query deletes the rows it matches and returns how many it deleted, or a violation, usually a foreign key whose `on_delete` is `:restrict` or unset, whose `constraint` and `columns` are the referencing table's foreign key, since that's the one that failed. Each write is one statement with no `RETURNING`, and its count is the one the driver gives for it, which leaves out rows a cascade changed. On a `Skyward::ORM::Projection`, from `into(RowClass)` anywhere before the write, each write returns rows of the row class instead, through `RETURNING` of just its members' columns, or every column for the table class itself: `insert(**values)` its one row, and `update` and `delete` an `Array`, so Steep types them as `RowClass | Skyward::ORM::Violation` and `Array[RowClass] | Skyward::ORM::Violation`. `insert` on a projection raises `ArgumentError` before any SQL runs, naming each clause, unless the query has nothing but `into`: conditions, even from a `where` or `exclude` given nothing, `into` expressions, a `join` or `left_join`, `order`, `group`, `limit` or `offset`. Each write checks its table class against the schema, as a query does, and runs inside the fiber's transaction if there is one. `update` and `delete` raise `ArgumentError` on a query `into` a class with expressions, or with a `join` or `left_join`, `order`, `group`, `limit` or `offset`, which PostgreSQL and SQLite don't both support there, and on one with no conditions from `where`, `exclude` or `or`, which would change every row, unless it's an explicit `Todo.all` that no `where` or `exclude` has narrowed, even one given nothing, so `Todo.all.into(Id).delete` deletes every row while `Todo.into(Id).delete` raises. `insert!`, `update!` and `delete!` return the same count or rows, or raise `Skyward::ORM::ViolationError`, which carries the violation and its message. A violation the plain methods return rolls back the `Skyward.transaction` block it's returned from. `insert_all` is still to come.
