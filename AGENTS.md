# Skyward

Four gems: `skyward-core/` (the namespace, the `skyward` command and RBS loading), `skyward-api/` (a web framework), `skyward-orm/` (an ORM) and `skyward/` (installs both, and adds `skyward new`). Each gem's `README.md` is its spec; read it before changing that gem.

## Workflow

- Run every chore through its `bin/` script (`bin/setup`, `bin/test`, `bin/lint`, `bin/typecheck`, `bin/rbs`, `bin/ci`), never rake directly. Run `bin/ci` before pushing.
- Never hand-edit generated files: `*/sig/generated` (`bin/rbs`). `bin/typecheck` fails when they're stale.
- PR titles are Conventional Commits with a scope naming the gem (`feat(api): ...`, `fix(orm): ...`, `core`, `skyward`), and become the squash commit on `main`. release-please builds the changelog from them.
- Build each gem only as far as its README specifies. The gems never require a Skyward gem they don't depend on: `skyward-api` and `skyward-orm` depend on `skyward-core` only, and never on each other.
- Work headless: never open a browser window or GUI app. Start a server on a non-default port, and stop it when you're done.

## Code layout

- Zeitwerk loads every gem, so file paths match constant names, in compact style (`class Skyward::API::Routing::Router`). Each gem's `version.rb` is the exception: it nests because the gemspec loads it first. A `Data.define` constant also nests inside its compact-style owner (`module Skyward::API::Endpoints; Route = Data.define(...)`), because rbs-inline only types one assigned to a bare constant name.
- Tests are Minitest spec style (`describe`/`it`) and mirror the code they test. Each gem's tests run in that gem's own bundle (its `Gemfile`), so they can't load a gem it doesn't depend on.

## Where a module goes

- **Public names.** `Skyward` holds no constant but the gems' namespaces (`Skyward::Core`, `Skyward::API`, `Skyward::ORM`, and `Skyward::Generator`, the `skyward` gem's) and the `skyward` gem's `VERSION`. A constant the gem's README tells apps to write is public. It lives directly in its gem's namespace (`Skyward::API::Request`), or in a public namespace there when it belongs to a family (`Skyward::API::Responses::NotFound`).
- **The `@rbs use` convention.** An app's file that names a gem's types in RBS starts with `# @rbs use Skyward::API::*` (one line per gem) and writes them relative to it (`Responses::NotFound`, `Request`), because RBS doesn't resolve names through the superclass. Docs and examples do the same. Their Ruby code outside RBS annotations writes public names in full, and so does a `#:` after an expression, which Steep reads as Ruby.
- **Gem roots.** Each gem's root namespace (`Skyward::API`, `Skyward::Core`), its `VERSION`, its `commands.rb` and an error its README names (`Skyward::Core::BootError`, `Skyward::API::ReturnTypeError`) stay at the gem's root.
- **Groups.** Everything else lives in one of its gem's groups, in the table below. A new module goes in the first group whose description fits it. A shared helper that no description fits goes in the first group, in table order, that uses it. When neither places it, add a group and its row in the same PR.
- **Helpers nest.** A module that only one other module uses nests under it (`Skyward::Core::Signatures::Loader`, `Skyward::API::CLI::Serve::Reloader`), unless that user is a gem root or a class apps subclass (`Skyward::ORM::Record`): what only `Skyward.app` or `Record` uses goes in a group.
- **Group names.** Never a top-level constant of Ruby, its default gems or Rack (`JSON`, `Rack`), a name the README tells apps to define (`App`), or a public name in the same gem's namespace (`Request`, `Responses`). An API class subclasses `Skyward::API`, so inside it every constant under `Skyward::API`, or under a module it includes, shadows the app's own constant of that name. A public name is there for the app to write, so its shadowing is accepted; a group's name would only shadow the names an app is likeliest to write there.
- A group whose root file isn't already a module or class gets a file that only declares it (`lib/skyward/api/cli.rb`), so rbs-inline types it.

| Gem | Group | Holds |
| --- | --- | --- |
| core | `Skyward::Core::CLI` | the `skyward` executable's registry and dispatch, and finding and running the executables its commands use |
| core | `Skyward::Core::Signatures` | generating, finding and loading RBS files |
| core | `Skyward::Core::Types` | turning RBS types into values |
| core | `Skyward::Core::Diagnostics` | pointing a boot error at its source: excerpts of Ruby and RBS files, and Did you mean suggestions |
| api | `Skyward::API::Endpoints` | what an API class declares and returns: route declarations and response helpers |
| api | `Skyward::API::Routing` | matching a request to an endpoint |
| api | `Skyward::API::Inputs` | reading and coercing an endpoint's keywords |
| api | `Skyward::API::Serializer` | writing a returned value as the response |
| api | `Skyward::API::OpenAPI` | the OpenAPI document and the API reference page |
| api | `Skyward::API::Middleware` | the Rack middleware `Skyward.app` wraps every app in, and the logger they write to |
| api | `Skyward::API::Assembly` | the parts `Skyward.app` builds the Rack app from, and the app it returns |
| api | `Skyward::API::CLI` | what the `skyward` commands run; `commands.rb` only registers them |
| orm | `Skyward::ORM::Tables` | what a table class declares and the rows it builds: its schema, its column types and its rows' methods |
| orm | `Skyward::ORM::Catalog` | the database's schema as an adapter reads it: its tables, columns, indexes and constraints |
| orm | `Skyward::ORM::Adapters` | what differs between databases: each adapter's connection, SQL types, codec, schema reads and violations |
| orm | `Skyward::ORM::Connection` | the session that holds the current database, and the pool |
| orm | `Skyward::ORM::Statements` | the SQL that queries and writes share: quoted names, columns checked against a table class, and the `INSERT` a table class writes |
| orm | `Skyward::ORM::Queries` | what `Query` and `Projection` share: a query's clauses, the SQL built from them and the reads that run it |
| orm | `Skyward::ORM::Migrations` | generating, writing, running and reporting migrations: the diff between table classes and the catalog, its edits and their SQL, and the versions table |
| orm | `Skyward::ORM::CLI` | what the `skyward` commands run; `commands.rb` only registers them |
| skyward | `Skyward::Generator::CLI` | what `skyward new` runs, and the app it writes; `commands.rb` only registers it |

## Ruby

- Skyward supports every Ruby that isn't end-of-life, and CI tests each one. Use only what the oldest supported Ruby has: until Ruby 3.3 reaches end-of-life on 31 March 2027, that means no `it` block parameter, so name block parameters.
- Functional style: return new values, and keep side effects behind injected collaborators.
- A class only for identity, lifecycle or state, including injected collaborators; otherwise a module of functions with `extend self`.
- Expected outcomes are returned as values (the row, or a symbol naming what went wrong) and matched with `case`/`when`. Steep 2.1 can't type-check `case`/`in`.

## Typing

- Steep runs `D::Ruby.all_error`: every diagnostic is an error. Fix the annotation or the code; never disable a diagnostic in the Steepfile. The only escape is a targeted inline suppression with a comment saying why.
- Each gem is its own Steep target, which sees only its own signatures and those of the Skyward gems it depends on.
- Annotate every method with rbs-inline doc style: one `# @rbs name: Type` per parameter plus `# @rbs return: Type`, never the one-line `#:` method form. A generic method, or a parameter typed with an interface whose name starts with `_`, takes the whole-method `# @rbs [T] (T value) -> Array[T]` form, which the per-parameter tags can't express.
- Constants, `Data.define` members and `attr_reader`s take a trailing `#: Type` on the same line. An `attr_reader` also needs a `# @dynamic name` line directly above it, or Steep reports `MethodDefinitionMissing`.
- Declare instance variables with `# @rbs @name: Type` at the top of the class, not with a private reader.
- `sig/manual/` holds hand-written signatures: interfaces, and the `module X; extend ::X; end` re-declaration every `extend self` module needs (rbs-inline drops `extend self`). Declare an interface only when two or more different objects satisfy it; a test fake is not a second implementer.

## Testing

- Every module of behaviour gets a test file, even if it's only a smoke test. A unit with no behaviour (pure constants, data definitions) needs no test file.
- Only test what can change. Static code (generated files, constants, trivial accessors) gets at most a smoke test. Generated code is pinned at its generator: test the generator, not each generated output.
- A test file tests only the concerns of the unit it's mapped to. If testing X requires driving Y's entry point, either the behaviour belongs in X's own file with collaborators injected, or Y's file is covering for a missing X test.
- Order tests the way the code is ordered, and test every branch in reason: every early return, conditional and error path.

## Releasing

- The gems release in lockstep: one version, and each pins the others exactly.
- release-please keeps a release PR open that bumps every gem's version, adds the changelog section and updates the lockfiles. Merging it tags the release, and `release.yml` publishes the gems with RubyGems trusted publishing. Never bump a version by hand.

## Comments

The default is no comment. Keep only a _why_ the code can't show (a non-local constraint, an external quirk, a deliberate tradeoff), at the line it explains. Never restate the code, repeat types the signatures state, or record history.
