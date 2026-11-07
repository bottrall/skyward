# Skyward

Four gems: `skyward-core/` (the namespace, the `skyward` command and RBS loading), `skyward-api/` (a web framework), `skyward-orm/` (an ORM) and `skyward/` (installs both). Each gem's `README.md` is its spec; read it before changing that gem.

## Workflow

- Run every chore through its `bin/` script (`bin/setup`, `bin/test`, `bin/lint`, `bin/typecheck`, `bin/rbs`, `bin/ci`), never rake directly. Run `bin/ci` before pushing.
- Never hand-edit generated files: `*/sig/generated` (`bin/rbs`). `bin/typecheck` fails when they're stale.
- PR titles are Conventional Commits with a scope naming the gem (`feat(api): ...`, `fix(orm): ...`, `core`, `skyward`), and become the squash commit on `main`. release-please builds the changelog from them.
- Build each gem only as far as its README specifies. The gems never require a Skyward gem they don't depend on: `skyward-api` and `skyward-orm` depend on `skyward-core` only, and never on each other.
- Work headless: never open a browser window or GUI app. Start a server on a non-default port, and stop it when you're done.

## Code layout

- Zeitwerk loads every gem, so file paths match constant names, in compact style (`class Skyward::API::Router`). Each gem's `version.rb` is the exception: it nests because the gemspec loads it first.
- Tests are Minitest spec style (`describe`/`it`) and mirror the code they test. Each gem's tests run in that gem's own bundle (its `Gemfile`), so they can't load a gem it doesn't depend on.

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
