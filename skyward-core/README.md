# Skyward Core

> [!CAUTION]
> Skyward is pre-1.0. Everything this README describes is built, as [Status](#status) lists, but parts of the [Skyward API](../skyward-api/README.md#status) and [Skyward ORM](../skyward-orm/README.md#status) specs aren't yet. Any release may change the API, so don't run it in production yet.

The plumbing that [Skyward API](../skyward-api/README.md) and [Skyward ORM](../skyward-orm/README.md) share. You don't add it to your Gemfile: each of them depends on it, at exactly the same version.

## What it owns

- **The `Skyward` namespace.** Skyward Core opens it, and every Skyward gem's Zeitwerk loader extends it. Each gem's names live in that gem's own namespace there: `Skyward::Core`, `Skyward::API` and `Skyward::ORM`.
- **The `skyward` command.** It comes with Skyward Core, so it's there whichever Skyward gems you install. Each gem adds its own commands to it.
- **Loading RBS signatures.** One loader finds your app's signatures and those of the gems it uses, for every Skyward gem.
- **Keeping `sig/generated` current.** One function regenerates your app's `sig/generated` from its Ruby with rbs-inline, and the Skyward commands that read types call it first, so you never run rbs-inline by hand. `skyward check` only checks it's current, for CI.
- **Reading RBS types.** One reader turns a signature into values that Skyward API and Skyward ORM each build their own mappings on, so a `Todo` read from the database and a `Todo` sent as JSON are the same thing.
- **`Skyward::Core::BootError`**, which every Skyward gem raises when your app can't boot, saying why.

## Adding commands

The `skyward` executable finds each installed gem's `lib/skyward/<gem>/commands.rb` with `Gem.find_files` and loads it, and that file registers the gem's commands:

```ruby
Skyward::Core::CLI.register("routes", "List every route and the method that serves it") do |args|
  # ...
end
```

`skyward` with no command, `skyward help`, `--help` or `-h` lists every registered command with its description. An unknown command prints the same list and exits with status 1. A command fails by exiting (`abort "why"`); one that returns has succeeded.

## Ruby

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026).

## Status

This README is the spec, and this section lists each part of it that's built, as it lands. The gem opens the `Skyward` namespace and sets up its loader.

- **The `skyward` command.** The executable loads each installed gem's `commands.rb`, `Skyward::Core::CLI.register` adds a command, and `skyward` lists them and runs one, as [Adding commands](#adding-commands) describes. For the commands to run other gems' executables, `Skyward::Core::CLI::Executable.find(name, feature: name)` returns the path of gem `name`'s executable `name` when `feature` can be required in the bundle `skyward` runs in, or `nil` otherwise, and `Skyward::Core::CLI::Executable::CAPTURE` runs a command with an environment in a directory and returns its output, errors included, and whether it succeeded.
- **Loading RBS signatures.** `Skyward::Core::Signatures.load(directory)` returns an `RBS::DefinitionBuilder` over every `.rbs` file under `directory`, the `sig/` of each Skyward gem that has registered it with `Skyward::Core::Signatures.register(path)`, and the `date` and `time` libraries. Skyward Core registers its own. A directory that doesn't exist contributes nothing. A file that doesn't parse, a name declared twice, or a class whose declarations disagree on its type parameters raises `Skyward::Core::BootError` naming the file and line.
- **Keeping `sig/generated` current.** `Skyward::Core::Signatures::Inline.generate(directory, rbs_inline:, capture:)` runs the rbs-inline executable at `rbs_inline` through `capture`, in `directory` and in its default opt-in mode, which reads only files marked `# rbs_inline: enabled`, over every `.rb` file there outside `test/`, `spec/`, `vendor/`, `tmp/` and hidden directories, into a scratch directory, as `skyward check` does. It then writes each file whose content differs to `directory`'s `sig/generated`, leaving the others untouched, removes each file there that rbs-inline no longer generates, and any directory that leaves empty, and returns `nil`. When rbs-inline fails, it changes nothing and returns a message with rbs-inline's output, for the command to report. With no `rbs_inline`, as in a bundle without rbs-inline, it runs nothing and returns `nil`, so the app runs with `sig/generated` as committed.
- **Reading RBS types.** `Skyward::Core::Types::Reader.new(builder, refinements: {})` takes the `RBS::DefinitionBuilder` that `Skyward::Core::Signatures.load` returns, and `read(type)` turns an RBS type into a frozen `Data` value from `Skyward::Core::Types`: a `Scalar` (`:integer`, `:float`, `:string`, `:bool`, `:date`, `:time` or `:untyped`), a `Literal` (a String, Integer, boolean or `nil`), an `Enum` of Symbols, a `Nullable`, an `ArrayOf`, a `HashOf` (a `Hash[String, T]`, of its values' type), a `Record` or `Named` class with `Field`s (a name, a type and whether it's required), a `Union`, or a `Refined`. It expands aliases, generic ones included, reads `T?` and `T | nil` as `Nullable` and a union of symbol literals as one `Enum`, and flattens nested unions, dropping duplicates. `refinements:` maps an alias's full name (`"::Skyward::ORM::uuid"`) to a Symbol (`:uuid`), so a gem can tell which alias a type was written with: an alias in it reads as a `Refined` of what the alias expands to (`type`) and that Symbol (`as`), wherever it's reached, directly, through another alias of it, or inside a `T?` (a `Nullable` of the `Refined`), an `Array[T]` or a record. Every other alias, and every alias when `refinements:` is left out, expands to what it names and keeps nothing of it. A class is `Named` when its RBS declares public instance `attr_reader`s, rbs-inline's `Data.define` output included: its fields come from its own declarations, in written order, across every file that reopens it, skipping `private` sections. A type it can't read, such as an interface, a tuple, a proc, a `Hash` whose keys aren't `String`s or a class with no readers, comes back as an `Unreadable` naming the type, the class and reader it was found at (`Todo#tags`) and what to use instead, for the caller to raise `Skyward::Core::BootError` with its own context. A class with no loaded Ruby class, or a type that refers to itself, raises `Skyward::Core::BootError`. `type_name(klass)` finds a Ruby class's RBS declaration (none for an anonymous class), and `method_type(type_name, method)` a method's signature, raising `Skyward::Core::BootError` when RBS can't build the class.
- **`Skyward::Core::BootError`**, for any Skyward gem to raise when an app can't boot.
