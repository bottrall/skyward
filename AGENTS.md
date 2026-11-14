# Skyward

Four gems: `skyward-core/` (the namespace, the `skyward` command and RBS loading), `skyward-api/` (a web framework), `skyward-orm/` (an ORM) and `skyward/` (installs both, and adds `skyward new`). Each gem's `README.md` is its spec; read it before changing that gem.

## Commands

Everything runs through its `bin/` script, never a tool directly (`rake`, `rubocop`, `steep`, `vitest`, `oxlint`, `tsc`, `vite`, `playwright`).

| Script                        | What it does                                                                  |
| ----------------------------- | ----------------------------------------------------------------------------- |
| `bin/setup`                   | Install dependencies on a fresh checkout                                      |
| `bin/test [paths]`            | Run the tests; pass files to run only those                                   |
| `bin/lint [--fix] [paths]`    | Check lint and formatting; `--fix` fixes what it can                          |
| `bin/typecheck`               | Type-check the code                                                           |
| `bin/generate [--watch]`      | Regenerate the generated files; `--watch` keeps them current                  |
| `bin/build`                   | Build what the repo ships                                                     |
| `bin/bench [names]`           | Run the benchmarks; pass names to run only those whose names start with one   |
| `bin/check`                   | `bin/lint --fix`, `bin/typecheck`, `bin/test`: run before calling a change done |
| `bin/ci`                      | Run exactly what CI runs, without fixes: run before pushing                   |

## Workflow

- `bin/test`, and so `bin/ci`, need a PostgreSQL at `TEST_POSTGRES_URL`; [CONTRIBUTING.md](CONTRIBUTING.md#postgresql) says how to run one.
- `bin/typecheck` fails when any gem's, example's or the benchmarks' `sig/generated` is out of date with its Ruby.
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
| orm | `Skyward::ORM::Connection` | the session that holds the current database, the pool, and the connection that reports each statement to `instrument:` |
| orm | `Skyward::ORM::Statements` | the SQL that queries and writes share: quoted names, columns checked against a table class, and the `INSERT` a table class writes |
| orm | `Skyward::ORM::Queries` | what `Query` and `Projection` share: a query's clauses, the SQL built from them and the reads that run it |
| orm | `Skyward::ORM::Migrations` | generating, writing, running and reporting migrations: the diff between table classes and the catalog, its edits and their SQL, and the versions table |
| orm | `Skyward::ORM::CLI` | what the `skyward` commands run; `commands.rb` only registers them |
| skyward | `Skyward::Generator::CLI` | what `skyward new` runs, and the app it writes; `commands.rb` only registers it |

## Ruby

- Skyward supports every Ruby that isn't end-of-life, and CI tests each one. Use only what the oldest supported Ruby has: until Ruby 3.3 reaches end-of-life on 31 March 2027, that means no `it` block parameter, so name block parameters.
- Expected outcomes are returned as values (the row, or a symbol naming what went wrong) and matched with `case`/`when`. Steep 2.1 can't type-check `case`/`in`.
- Each gem is its own Steep target, which sees only its own signatures and those of the Skyward gems it depends on.
- A generic method, or a parameter typed with an interface whose name starts with `_`, takes the whole-method `# @rbs [T] (T value) -> Array[T]` form, which the per-parameter tags can't express.
- `Data.define` members take a trailing `#: Type` on the same line, like constants and `attr_reader`s.
- Declare instance variables with `# @rbs @name: Type` at the top of the class, not with a private reader.
- The `extend self` re-declaration in `sig/manual/` is `module X; extend ::X; end`.

## Releasing

- The gems release in lockstep: one version, and each pins the others exactly.
- release-please keeps a release PR open that bumps every gem's version, adds the changelog section and updates the lockfiles. Merging it tags the release, and `release.yml` publishes the gems with RubyGems trusted publishing. Never bump a version by hand.

## Code style

- Prefer functional style: enumerable / array methods (`map`, `filter`, `reduce`) over manual loops.
- Favor immutability — return new values rather than mutating arguments.
- Write pure functions where possible; isolate side effects (I/O, DB, network) behind clear boundaries.
- Use a class only when an instance has identity, lifecycle, or mutable state. Otherwise use a module of pure functions. A class whose methods are all static (`self.foo`) is a module wearing pants.
- Default to composition — pass collaborators ("has-a") rather than inheriting from a parent ("is-a"). For shared _shape_, use an interface, structural type, or duck typing. Reserve inheritance for genuine "is-a" with shared _implementation_, or framework-mandated parents (`ApplicationRecord`, `Sidekiq::Worker`, custom `Error` subclasses).
- Don't use thrown exceptions for control flow — return an explicit result type, or follow the pattern this repo already uses. Reserve `throw` / `raise` for truly exceptional circumstances: programmer errors, unrecoverable state, framework-level boundaries.

### Dependency injection

Don't construct or reach for collaborators inside a function or class — accept them as constructor or function parameters, typed as the **smallest interface** that captures what the function actually uses (`Emailer` with a `send` method, not `SendgridEmailService` with its 40-method API). Wire concrete implementations at the **application edge** — `main`, the entry point, a composition root.

**Smell:** a function or class taking 8+ dependencies is doing too much — split it.

**Exempt:** framework globals that ship first-class test seams — Rails `ActiveRecord` (`User.find`, `user.save`), `ActionMailer` (`UserMailer.welcome(user).deliver_later`), `ActiveJob`. The test database, `ActionMailer::TestHelper`, and `perform_enqueued_jobs` already provide the seam DI exists to create, so calling them in place costs none of the testability or swappability the rule protects. The rule still binds collaborators that lack such a seam: third-party clients (`Stripe::Client`, an HTTP or S3 SDK) and this repo's own service objects — inject those.

## Testing

- Every module of behaviour gets a test file, even if it's only a smoke test. A unit with no behaviour — pure constants, data definitions, types — needs no test file.
- Only test what can change. Static code — generated files, constants, trivial accessors — gets at most a smoke test. Generated code is pinned at its generator: test the generator, not each generated output.
- A test file tests only the concerns of the unit it's mapped to. If testing X requires driving Y's entry point, either the behaviour belongs in X's own file with collaborators injected, or Y's file is covering for a missing X test. A behaviour belongs to the unit whose contract it is, even when observing it means calling through an object that unit returns. A composer's tests assert the composer's outcomes only — never a collaborator's branches, which are pinned in the collaborator's own file.
- Order tests the way the code is ordered: they follow the source's structure, and within a routine they follow execution order (validation behaviour first).
- Test all branches in reason: every early return, conditional, and error path gets a test — unless the branch is dead or a programmer-error tripwire.
- One assertion per test: each `it` makes exactly one `assert_*` or `expect`. A test that wants two is two tests.
- Never mock code you own. Don't patch a module, method or import to change what it does (`vi.mock`, `vi.spyOn`, `Minitest::Mock`, `stub`); pass the unit a fake through the parameters it already takes its collaborators by.

## Ruby typing

- Steep runs `D::Ruby.all_error`: every diagnostic is an error. Fix the annotation or the code; never disable a diagnostic in the Steepfile. The only escape is a targeted inline suppression with a comment saying why.
- Annotate every method in `lib/` with rbs-inline doc style: one `# @rbs name: Type` per param plus `# @rbs return: Type`, never the one-line method-type or `#:` method form. Constants and `attr_reader`s rbs-inline can't infer take a trailing `#: Type` on the same line; one on the line above is ignored.
- An `attr_reader`/`attr_writer` needs a `# @dynamic name` line directly above it, or Steep reports `MethodDefinitionMissing`.
- Declare an interface only when different objects satisfy it — two or more implementers, or a contract a consumer implements — or when a boundary forbids naming the one class. When only one class is ever passed, annotate that class; a test fake is not a second implementer.
- `sig/generated/` is written by `bin/generate` from the inline annotations: never hand-edit it, and commit it with the `lib/` change that moved it.
- `sig/manual/` mirrors `lib/` for hand-written signatures rbs-inline can't generate: interfaces, and the `extend self` re-declaration every `extend self` module needs (rbs-inline drops `extend self`). A type alias may instead be declared inline with `# @rbs!` beside the code that uses it.
- `sig/_private/` holds stubs for gaps in stdlib and third-party signatures, one file per gem or library (`open3.rbs`). Check the gem's own RBS and gem_rbs_collection before writing one, and delete the stub once real signatures exist. RBS skips `_`-prefixed directories in library mode, so the stubs never reach projects that install this one.

## Comments and documentation

**The default is no comment.** Names, types, and structure carry the meaning; when they don't, fix them rather than explain them. Delete the comment and read the code cold: if the intent is still recoverable, it stays deleted. Keep only a _why_ the code can't show — a non-local constraint, an external quirk, a deliberate tradeoff, a safety invariant — and put it at the line it explains, not in a header.

Never: a restatement of the code (appending "so that…" doesn't rescue it), types the type system already states, or history ("was X, now Y").

Documentation lives in the guides, not in comments. What a signature can't express — what a method raises, ordering guarantees, what an implementer must honour — is documented there.
