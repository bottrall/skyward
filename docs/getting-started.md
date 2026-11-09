# Getting started with Skyward

This guide takes you from installing Skyward to a running, tested, documented API. It's written for Skyward 0.3. Each step shows the command to run, the code to write and the output to expect. Where output is long, `...` marks what's left out. Timestamps, request IDs and test seeds will differ on your machine, and on Ruby 3.3 hashes print as `{:title=>"Buy milk"}` rather than `{title: "Buy milk"}`.

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
Wrote todos/db/migrate/20261109000000_create_notes.sql
Wrote todos/modules/notes/api.rb
Wrote todos/modules/notes/record.rb
Wrote todos/modules/notes.rb
Wrote todos/rbs_collection.yaml
Wrote todos/sig/generated/app.rbs
Wrote todos/sig/generated/boot.rbs
Wrote todos/sig/generated/modules/notes/api.rbs
Wrote todos/sig/generated/modules/notes/record.rbs
Wrote todos/sig/generated/modules/notes.rbs
Wrote todos/test/app_test.rb
Wrote todos/test/modules/notes/api_test.rb
Wrote todos/test/test_helper.rb
...
Bundle complete! 7 Gemfile dependencies, 62 gems now installed.
Use `bundle info [gemname]` to see where a bundled gem is installed.
Next: cd todos && bin/setup
```

`bin/setup` installs the gems, downloads the signatures that Steep, the type checker, needs for them, and creates the development database at `db/todos.sqlite3`:

```sh
$ cd todos
$ bin/setup
...
Bundle complete! 7 Gemfile dependencies, 62 gems now installed.
...
It's done! 20 gems' RBSs now installed.
Migrated 20261109000000
```

From here on, every command runs in the `todos` directory.

## 3. A tour of the app

The app is an API with no frontend. It comes with one small resource, notes, for you to copy. The files that matter most:

- `modules/notes/record.rb` is `Notes::Record`, a table class. Each typed `attr_reader` is a column, and each row comes back as a frozen instance of the class.
- `modules/notes/api.rb` is `Notes::API`, the notes endpoints. An endpoint is a public method: its keywords are its inputs, and what it returns is the response.
- `app.rb` builds the app and wires each API to what it needs. It's the one place that does.
- `boot.rb` loads `modules/` and connects to the database: `DATABASE_URL` if it's set, and otherwise SQLite at `db/todos.sqlite3`.
- `db/migrate/` holds the migrations, as plain SQL.
- `sig/generated/` holds the type signatures, generated from the `#:` and `# @rbs` comments in the Ruby. You never edit it by hand.
- `test/` holds the tests, and `bin/test` and `bin/ci` run them.
- `AGENTS.md` teaches a coding agent working in the app its conventions. It's a good read for people too.

The table class:

```ruby
# modules/notes/record.rb
# frozen_string_literal: true

# rbs_inline: enabled

class Notes::Record < Skyward::ORM::Record
  table :notes
  check :title, length: 1..200

  # @dynamic id, title, body
  attr_reader :id     #: Integer
  attr_reader :title  #: String
  attr_reader :body   #: String?
end
```

The app, which mounts the notes endpoints at `/notes` and passes them the table class to query:

```ruby
# app.rb
# frozen_string_literal: true

# rbs_inline: enabled

require_relative "boot"

App = Skyward.app(docs: true, title: "Todos") do |app|
  app.mount Notes::API.new(notes: Notes::Record), at: "/notes"
end #: Skyward::API::_RackApp
```

[Starting an app](../skyward/README.md#starting-an-app) lists every file.

## 4. Add a column

Let a note be pinned. Add a `pinned` column to the table class, with a default, so the notes already in the table get one:

```ruby
# modules/notes/record.rb
# frozen_string_literal: true

# rbs_inline: enabled

class Notes::Record < Skyward::ORM::Record
  table :notes
  check :title, length: 1..200
  default pinned: false

  # @dynamic id, title, body, pinned
  attr_reader :id      #: Integer
  attr_reader :title   #: String
  attr_reader :body    #: String?
  attr_reader :pinned  #: bool
end
```

Skyward reads column types from the signatures in `sig/generated`, so regenerate them:

```sh
$ bundle exec rbs-inline --output=sig/generated *.rb modules
🎉 Generated 1 RBS files under sig/generated
```

## 5. Migrate the database

Skyward writes the migration for you, by comparing the table class with the database:

```sh
$ bundle exec skyward migration add_pinned_to_notes
Notes::Record differs from the notes table:
  + pinned  INTEGER NOT NULL
Wrote db/migrate/20261109160824_add_pinned_to_notes.sql. Review it, then run `skyward migrate`.
```

Review the SQL before you run it. It's yours to edit and commit:

```sql
-- db/migrate/20261109160824_add_pinned_to_notes.sql
ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;

-- down
ALTER TABLE notes DROP COLUMN pinned;
```

The SQL is written for the database the app connects to, here SQLite, which stores a `bool` as an `INTEGER` that's 0 or 1. The `-- down` section is what `skyward rollback` runs.

Then run it:

```sh
$ bundle exec skyward migrate
Migrated 20261109160824
```

## 6. Add a typed endpoint

Add an endpoint that pins a note. Its route goes at the top of the class with the others, and its method below them:

```ruby
# modules/notes/api.rb
# frozen_string_literal: true

# rbs_inline: enabled

# @rbs use Skyward::API::*

class Notes::API < Skyward::API
  description "Notes, each a title and an optional body."

  get  "/",        to: :index,  summary: "List notes, newest first."
  get  "/:id",     to: :show,   summary: "Fetch a single note."
  post "/",        to: :create, summary: "Write a note."
  post "/:id/pin", to: :pin,    summary: "Pin a note."

  # ... the existing methods ...

  # @rbs id: Integer
  # @rbs return: Notes::Record | Responses::NotFound
  def pin(id:)
    @notes.where(id:).update!(pinned: true).first || not_found
  end
end
```

The `# @rbs` lines are the endpoint's contract. `id: Integer` makes Skyward turn the `"1"` in `/notes/1/pin` into `1`, and answer 422 for `/notes/abc/pin` before the method runs. The return type says the endpoint answers with a note or a 404, and that goes into the API's documentation. `update!` returns the rows it changed, so there's no row when no note has the `id`, and the endpoint answers 404.

Regenerate the signatures, then list the routes to see the new one with its signature:

```sh
$ bundle exec rbs-inline --output=sig/generated *.rb modules
🎉 Generated 1 RBS files under sig/generated
$ bundle exec skyward routes
GET   /notes          Notes::API#index   (?limit: Integer) -> Array[Notes::Record]
GET   /notes/:id      Notes::API#show    (id: Integer) -> (Notes::Record | Responses::NotFound)
POST  /notes          Notes::API#create  (body: NewNote) -> (Responses::Created[Notes::Record] | Responses::Unprocessable)
POST  /notes/:id/pin  Notes::API#pin     (id: Integer) -> (Notes::Record | Responses::NotFound)
```

## 7. Run it

```sh
$ bundle exec skyward serve
{"time":"...","severity":"info",...,"message":"Falcon v0.57.0 taking flight! ...\n- Binding to: #<Falcon::Endpoint http://localhost:9292/ {}>\n..."}
...
```

It serves the app on port 9292, or on `PORT` if you set it, and reloads it whenever you change a file. Every request logs one line of JSON. In another terminal, write a note:

```sh
$ curl -i -X POST localhost:9292/notes -H "content-type: application/json" -d '{"title":"Buy milk","body":"Oat, not dairy"}'
HTTP/1.1 201 Created
content-type: application/json
x-request-id: b2de5bbb-9f8d-439b-b969-c0754f097583
vary: accept-encoding
content-length: 66

{"id":1,"title":"Buy milk","body":"Oat, not dairy","pinned":false}
```

Pin it, and list the notes:

```sh
$ curl -X POST localhost:9292/notes/1/pin
{"id":1,"title":"Buy milk","body":"Oat, not dairy","pinned":true}
$ curl localhost:9292/notes
[{"id":1,"title":"Buy milk","body":"Oat, not dairy","pinned":true}]
```

The types do their work on requests that don't fit. A note that doesn't exist is a 404, an `id` that isn't a number is refused before the method runs, and the database refuses an empty title:

```sh
$ curl -X POST localhost:9292/notes/42/pin
{"type":"about:blank","title":"Not Found","status":404}
$ curl -X POST localhost:9292/notes/abc/pin
{"type":"about:blank","title":"Unprocessable Content","status":422,"errors":[{"at":"path.id","message":"expected Integer, got \"abc\""}]}
$ curl -X POST localhost:9292/notes -H "content-type: application/json" -d '{"title":""}'
{"type":"about:blank","title":"Unprocessable Content","status":422,"detail":"A title needs 1 to 200 characters"}
```

Now open <http://localhost:9292/docs> in your browser. It's the API reference, built from the routes, their summaries and their signatures, `POST /notes/{id}/pin` included. The page itself is small, and loads [Scalar](https://github.com/scalar/scalar) to render the OpenAPI document at `/openapi.json`:

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

## 8. Test it

An endpoint is a method on a plain object, so the fastest test calls it. Add to `test/modules/notes/api_test.rb`, inside `describe Notes::API`:

```ruby
describe "#pin" do
  it "answers the note, pinned" do
    note = write

    assert_equal note.with(pinned: true), api.pin(id: note.id)
  end

  it "answers 404 for a note that doesn't exist" do
    assert_instance_of Skyward::API::Responses::NotFound, api.pin(id: 0)
  end
end
```

Rows are values, so the test compares them with `==`. `write` is a helper already in the file, which inserts a note.

To test the whole stack, routing and the `id:` conversion included, use `Skyward::API::Test.client`, which calls the app in-process without a server. Add to `test/app_test.rb`, inside `describe "App"`:

```ruby
describe "POST /notes/:id/pin" do
  it "answers the note, pinned" do
    response = client.post("/notes/#{write.json[:id]}/pin")

    assert_equal [200, true], [response.status, response.json[:pinned]]
  end

  it "answers 422 for an id that isn't a number" do
    response = client.post("/notes/abc/pin")

    assert_equal [422, "path.id"], [response.status, response.json[:errors].first[:at]]
  end
end
```

Each test runs in a transaction that's rolled back after it, on a database of its own, so the tests never see your development notes. Run them:

```sh
$ bin/test
Run options: --seed 41342

# Running:

...........F....

Finished in 0.006895s, 2320.4477 runs/s, 2465.4757 assertions/s.

  1) Failure:
App::POST /notes#test_0001_answers 201 with the new note [test/app_test.rb:34]:
--- expected
+++ actual
@@ -1 +1 @@
-[201, {title: "Buy milk", body: "Today"}]
+[201, {title: "Buy milk", body: "Today", pinned: false}]


16 runs, 17 assertions, 1 failures, 0 errors, 0 skips
...
```

The new tests pass, but one that came with the app fails: it checks every field of a new note, and a note now has `pinned` too. Add it to what the test expects, on line 34 of `test/app_test.rb`:

```ruby
assert_equal [201, { title: "Buy milk", body: "Today", pinned: false }], [response.status, response.json.except(:id)]
```

```sh
$ bin/test
Run options: --seed 14087

# Running:

................

Finished in 0.005640s, 2837.0002 runs/s, 3014.3127 assertions/s.

16 runs, 17 assertions, 0 failures, 0 errors, 0 skips
```

## 9. Run CI

`bin/ci` runs everything CI should: it regenerates the signatures and fails if that changed them, runs the tests, then runs `skyward check`, which checks the signatures again, boots the app in strict mode, so an endpoint without types fails it, and type-checks the code with Steep. Run it before you push:

```sh
$ bin/ci
...
🎉 Generated 5 RBS files under sig/generated
Run options: --seed 25242

# Running:

................

Finished in 0.004997s, 3201.8955 runs/s, 3402.0140 assertions/s.

16 runs, 17 assertions, 0 failures, 0 errors, 0 skips
Migrated 20261109000000
Migrated 20261109160824
Signatures: passed
Strict boot: passed
Steep: passed
# Type checking files:

..........

No type error detected. 🫖
```

The two `Migrated` lines are for a database `bin/ci` makes for `skyward check` and deletes after, not your development database.

## 10. Hand the API to its consumers

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
