# Skyward

> [!CAUTION]
> **Work in progress: Skyward doesn't do anything yet.** Version 0.1 is a skeleton. The gems install and load, but none of the features described here are built. This README is the spec for what's coming, not documentation of what exists. Don't depend on it yet.

Typed Ruby web apps, where an endpoint is a method and a row is a value. This gem installs both halves of Skyward:

- [Skyward API](../skyward-api/README.md), a web framework where an endpoint is a method, typed with RBS.
- [Skyward ORM](../skyward-orm/README.md), an ORM where a class is a table and its rows are frozen values, typed with RBS.

Each works without the other. Add this gem when you want both.

## Install

```ruby
# Gemfile
gem "skyward"
```

```ruby
require "skyward" # requires skyward/api and skyward/orm
```

Skyward supports every Ruby that isn't end-of-life (3.3 and later, as of November 2026).

## Starting an app

```sh
$ skyward new todos
```

`skyward new` writes a working app: `app.rb` and `boot.rb`, a `Steepfile` with typing set up, tests, `bin/ci`, and an `AGENTS.md` that teaches an agent working in the app its conventions.

## Status

This README is the spec. Skyward 0.1 is a skeleton: `require "skyward"` loads both gems, and `skyward new` isn't built yet. It arrives once Skyward API and Skyward ORM are both built.

- **One reading of each type.** The `skyward` gem's tests hold Skyward API and Skyward ORM to the promise both READMEs make, that a row read from the database and the same class sent as JSON are the same thing, on SQLite and on PostgreSQL. A table class with a column of every type both read (`Integer`, `Float`, `String`, `bool`, `Date`, `Time` and a union of symbols, and a nullable one of each) makes the round trip: a row the ORM inserts, returned from an endpoint typed with the class, read back with `Skyward::API::Test.client` and posted to an endpoint that takes the class as `body:`, arrives `==` to the row the database holds, a `Time` with microseconds and a non-UTC offset included. The class's OpenAPI component and the ORM's columns agree, field by field, on name, type, nullability and enum values. The types only one gem reads are listed in the test, so teaching either gem a type means updating the list: for now `Hash[String, T]`, `Array[T]`, records, classes with typed readers, unions of them and literals are read by Skyward API alone, and `BigDecimal` by neither.
