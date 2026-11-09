# frozen_string_literal: true

require "skyward/orm"

discover = -> { Skyward::ORM::Migrations::Discovery.table_classes(Zeitwerk::Loader) }

Skyward::Core::CLI.register(
  "migration",
  "Write the migration that brings the database in line with your table classes"
) do |args|
  Skyward::ORM::CLI::Migration.run(
    args,
    directory: Dir.pwd,
    time: Time.now,
    input: $stdin,
    out: $stdout,
    kernel: Kernel,
    session: Skyward::ORM::Connection::SESSION,
    discover:
  )
end

Skyward::Core::CLI.register("migrate", "Run the pending migrations in db/migrate") do |_args|
  Skyward::ORM::CLI::Migrate.run(
    directory: Dir.pwd,
    out: $stdout,
    kernel: Kernel,
    session: Skyward::ORM::Connection::SESSION,
    discover:
  )
end

Skyward::Core::CLI.register("rollback", "Undo the latest migration by running its -- down section") do |_args|
  Skyward::ORM::CLI::Rollback.run(
    directory: Dir.pwd,
    out: $stdout,
    kernel: Kernel,
    session: Skyward::ORM::Connection::SESSION
  )
end

Skyward::Core::CLI.register(
  "status",
  "List which migrations have run, and how your table classes differ from the database"
) do |_args|
  Skyward::ORM::CLI::Status.run(
    directory: Dir.pwd,
    out: $stdout,
    kernel: Kernel,
    session: Skyward::ORM::Connection::SESSION,
    discover:
  )
end
