# Skyward Core

> [!CAUTION]
> **Work in progress: Skyward Core is barely started.** Version 0.1 is a skeleton. The gems install and load, and only the parts [Status](#status) lists are built. This README is the spec for what's coming, not documentation of what exists. Don't depend on it yet.

The plumbing that [Skyward API](../skyward-api/README.md) and [Skyward ORM](../skyward-orm/README.md) share. You don't add it to your Gemfile: each of them depends on it, at exactly the same version.

## What it owns

- **The `Skyward` namespace.** Skyward Core opens it, and every Skyward gem's Zeitwerk loader extends it.
- **The `skyward` command.** It comes with Skyward Core, so it's there whichever Skyward gems you install. Each gem adds its own commands to it.
- **Loading RBS signatures.** One loader finds your app's signatures and those of the gems it uses, for every Skyward gem.
- **Reading RBS types.** One reader turns a signature into values that Skyward API and Skyward ORM each build their own mappings on, so a `Todo` read from the database and a `Todo` sent as JSON are the same thing.
- **`Skyward::BootError`**, which every Skyward gem raises when your app can't boot, saying why.

## Adding commands

The `skyward` executable finds each installed gem's `lib/skyward/<gem>/commands.rb` with `Gem.find_files` and loads it, and that file registers the gem's commands:

```ruby
Skyward::Commands.register("routes", "List every route and the method that serves it") do |args|
  # ...
end
```

`skyward` with no command, `skyward help`, `--help` or `-h` lists every registered command with its description. An unknown command prints the same list and exits with status 1. A command fails by exiting (`abort "why"`); one that returns has succeeded.

## Ruby

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026).

## Status

This README is the spec. Skyward 0.1 is a skeleton: the gem installs, opens the `Skyward` namespace and sets up its loader. This section lists each part as it lands.

- **The `skyward` command.** The executable loads each installed gem's `commands.rb`, `Skyward::Commands.register` adds a command, and `skyward` lists them and runs one, as [Adding commands](#adding-commands) describes. No gem registers a command yet.
