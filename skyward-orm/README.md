# Skyward ORM

> [!CAUTION]
> **Work in progress: Skyward ORM doesn't do anything yet.** Version 0.1 is a skeleton. The gems install and load, but none of the features described here are built. This README is the spec for what's coming, not documentation of what exists. Don't depend on it yet.

A small, fast Ruby ORM where **a class is a table and its rows are values**.

You write a plain Ruby class with a typed reader for each column, and tell Skyward ORM which table it lives in. The class is then the table: you query it, write to it and migrate it. What comes back are immutable instances of your class. There are no callbacks, no dirty tracking and no lazy loading. You get your data and the SQL that fetched it.

Skyward ORM is half of Skyward. The other half is [Skyward API](../skyward-api/README.md), but each works without the other.

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

Todo.insert(title: "Buy milk")
# => #<Todo id=1, title="Buy milk", done=false>

Todo.where(done: false).map(&:title)
# => ["Buy milk"]

Todo.where(id: 1).update(done: true)
# => [#<Todo id=1, title="Buy milk", done=true>]
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
- [Coming from…](#coming-from)
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
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  list_id     bigint      NOT NULL REFERENCES lists ON DELETE CASCADE,
  title       text        NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  priority    text        NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
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
Wrote db/migrate/20261019141500_add_notes_to_todos.sql.
```

- **Migrations are plain SQL files you commit.** Read them, edit them, and add data backfills to the same file. Skyward ORM runs each one once, in order, inside a transaction. `skyward rollback` runs the `-- down` section.
- **Skyward ORM asks when it can't know what you meant.** If a column disappears and another appears, it asks whether you renamed it, rather than dropping your data.
- **Generation needs types.** A column without a `#:` type still works at runtime, but Skyward ORM can't guess its SQL type. The migration gets `-- TODO: todos.notes needs a type`, and you write that line yourself.
- **A new required column needs a default.** The rows already in the table need a value for it, so the migration gets `-- TODO: todos.notes needs a DEFAULT for the rows todos already has`. Give it one, or make the column nullable.
- **Hand-written migrations are always an option.** `skyward migration --empty backfill_priorities` gives you an empty file for SQL you write yourself.

Business rules like the title length live in the database, where they hold for every writer, and they come back to Ruby as a [`Violation`](#when-the-database-says-no).

---

## Connecting

```ruby
Skyward.connect(ENV.fetch("DATABASE_URL"), pool: 10)
```

Call it once, where your app boots. Skyward ORM reads your column types from the `.rbs` files under `sig/`, or the directory you pass as `signatures:`.

Like ActiveRecord, Skyward ORM keeps the connection for you, so `Todo.where(...)` just works. Also like ActiveRecord, it gives you the seams that make that safe: tests that each run in a rolled-back transaction, and `Skyward.using(other_database) { ... }` to switch databases for one block. The switch applies only to the current fiber, never globally.

When you connect, Skyward ORM compares every loaded table class with the live schema and refuses to start if they disagree:

```
Skyward::ORM::SchemaMismatch: Todo doesn't match the todos table

  notes     todos has no column notes.
            Run `skyward migrate`, or `skyward migration` if you haven't generated one.
```

A table class loaded after connect is checked the first time it's used.

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

| Ruby                                     | SQL                                                         |
| ---------------------------------------- | ----------------------------------------------------------- |
| `where(done: false)`                     | `done = false`                                              |
| `where(due_on: nil)`                     | `due_on IS NULL`                                            |
| `where(priority: [:high, :normal])`      | `priority IN ('high', 'normal')`                            |
| `where(due_on: ..Date.today)`            | `due_on <= '2026-10-18'`                                    |
| `where(due_on: Date.today...)`           | `due_on >= '2026-10-18'`                                    |
| `where(created_at: from...to)`           | `created_at >= ? AND created_at < ?`                        |
| `exclude(done: true)`                    | `NOT (done = true)`                                         |
| `where(done: false).or(priority: :high)` | `done = false OR priority = 'high'`                         |
| `where("title ILIKE ?", "%milk%")`       | `title ILIKE '%milk%'`, with the value bound as a parameter |

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
Todo.where(done: false, priority: [:high, :normal]).order(created_at: :desc).to_sql
# => ["SELECT id, list_id, title, priority, due_on, done, created_at FROM todos
#      WHERE done = $1 AND priority IN ($2, $3) ORDER BY created_at DESC",
#     [false, "high", "normal"]]
```

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

`join` is an inner join and `left_join` is a left join. A member without an expression reads from the table the query started from, so `id` above is `todos.id`. A joined table's columns always need an expression.

---

## Raw SQL

Skyward ORM builds SQL. It doesn't hide it. When a query is easier to write than to build, write it, and name the shape you want back:

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

Writes return what they wrote, using `RETURNING`, so you never need a second query to see the result:

```ruby
Todo.insert(title: "Buy milk", list_id: 1)              # => Todo
Todo.insert_all([{ title: "Eggs", list_id: 1 }, ...])   # => Array[Todo]
Todo.where(id: 42).update(done: true)                   # => Array[Todo], the updated rows
Todo.where(done: true).delete                           # => Array[Todo], the deleted rows
```

Columns with a default (`id`, `done`, `created_at`) and nullable ones (`due_on`) are optional. The rest are required, and leaving one out raises an `ArgumentError` straight away.

### When the database says no

A duplicate email or a missing parent row isn't exceptional. It's an outcome your code should handle. So the plain write methods return either the rows or a `Skyward::ORM::Violation`:

```ruby
result = User.insert(email:)
case result
when User then created result
else result.kind == :unique ? conflict("That email is already registered") : unprocessable(result.message)
end
```

Steep 2.1 can't type-check `case`/`in`, so typed code matches on the class with `case`/`when`, and on the violation's `kind`.

`Skyward::ORM::Violation` has `kind` (`:unique`, `:foreign_key`, `:not_null` or `:check`), `constraint`, `columns` and the database's `message`.

When a violation would mean a bug, use the bang version. It returns the rows or raises `Skyward::ORM::ViolationError`, the way `save` and `save!` work in ActiveRecord:

```ruby
Todo.insert!(title: "Buy milk", list_id: 1) # => Todo
```

---

## Transactions

```ruby
Skyward.transaction do
  list = List.insert!(name: "Groceries")
  Todo.insert!(title: "Milk", list_id: list.id)
end
```

Every query inside the block runs in the transaction, and the block's value is returned. Skyward ORM rolls back if the block raises, **or if it returns a `Skyward::ORM::Violation`**, so the non-bang methods compose:

```ruby
result = Skyward.transaction do
  user = User.insert(email:)
  case user
  when User then Membership.insert(user_id: user.id, team_id:)
  else user # a violation: rolls back, then returns it
  end
end
```

A transaction belongs to the fiber that opened it. Ruby copies fiber storage into child fibers and threads, so a task started inside the block would otherwise share its connection. Skyward ORM raises if one tries to use it: "this transaction belongs to another fiber; start your own, or return the result to the block". `Skyward.transaction?` tells you whether you're inside one.

---

## Types

Skyward ORM reads the same RBS as Steep, whether it's written inline or in `sig/`. It reads the `.rbs` files, so inline types count once rbs-inline has written them to `sig/`. Here's what gets checked, and when:

| When                          | What's checked                                                                                                                                                                                                       |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **As you type (Steep)**       | The row type of every query. `Todo.where(...)` is a `Skyward::ORM::Query[Todo]`, `.to_a` is an `Array[Todo]`, `.into(TodoTitle)` is a `Query[TodoTitle]`, and `insert` returns `Todo \| Skyward::ORM::Violation`. No annotations are needed. |
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
Skyward.connect(ENV.fetch("TEST_DATABASE_URL"))
Skyward.migrate("db/migrate") # runs any migration the test database hasn't had
```

```ruby
describe Todo do
  include Skyward::ORM::Transactional # each test runs in a transaction that's rolled back afterwards

  let(:list) { List.insert!(name: "Home") }

  describe ".overdue" do
    it "skips todos that are done" do
      late = Todo.insert!(title: "Milk", list_id: list.id, due_on: Date.new(2026, 10, 1))
      Todo.insert!(title: "Eggs", list_id: list.id, due_on: Date.new(2026, 10, 1), done: true)

      assert_equal [late], Todo.overdue(today: Date.new(2026, 10, 18)).to_a
    end
  end
end
```

Rows are values, so assertions compare them directly with `==`.

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
| `skyward status`                       | lists migrations, and any differences between your classes and the database   |
| `skyward scaffold todos`               | prints a table class for an existing table, for adopting a database Skyward ORM didn't create |

The CLI runs in your app's directory and requires its `boot.rb`, which loads your table classes and calls `Skyward.connect`.

---

## Coming from…

- **ActiveRecord.** `Todo.where` works the way you expect, and `insert`/`insert!` work like `save`/`save!`. But a row is data rather than an object with a lifecycle: it has no callbacks, validations or associations. The columns are written in the class, so you can see them, and migrations are written for you from them.
- **Sequel.** It's the same idea of queries as values, but the rows are instances of your own typed classes rather than hashes or models.
- **Django or Prisma.** It's the same declare-then-generate approach to migrations, in plain Ruby with RBS types.
- **Raw SQL.** Use it whenever you like (`Skyward.query`), and keep typed results and bound parameters.

---

## Design principles

1. **A class is a table, and its rows are values.** You query the class, and you get back frozen instances of it that you can use anywhere.
2. **The class is the schema.** Columns, types and constraints are declared once, in Ruby, where Steep and Skyward ORM can both read them. Migrations follow from them.
3. **A query is a value.** It's immutable, composable and printable, and nothing runs until you ask for rows.
4. **SQL is the feature, not the problem.** Skyward ORM builds the SQL you'd write yourself, writes your migrations in SQL you can read, and lets you write it yourself when that's clearer.
5. **Outcomes are values.** The database saying no is a result you handle, not an exception you rescue.
6. **No hidden work.** Skyward ORM has no lazy loading and no callbacks. Every query is one you can see.

---

## Status

This README is the spec. Skyward 0.1 is a skeleton: the gem installs and loads, and none of the features above are built yet. Skyward ORM is built after Skyward API, and this section lists each part as it lands.
