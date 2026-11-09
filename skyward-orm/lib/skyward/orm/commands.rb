# frozen_string_literal: true

require "skyward/orm"

Skyward::Core::CLI.register(
  "migration",
  "Write the migration that brings the database in line with your table classes"
) do |args|
  Skyward::ORM::CLI::Migration.run(
    args,
    directory: Dir.pwd,
    time: Time.now,
    out: $stdout,
    kernel: Kernel,
    session: Skyward::ORM::Connection::SESSION,
    discover: -> { Skyward::ORM::Migrations::Discovery.table_classes(Zeitwerk::Loader) }
  )
end
