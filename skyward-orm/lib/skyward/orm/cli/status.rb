# frozen_string_literal: true

module Skyward::ORM::CLI::Status
  extend self

  # Status only reports, so it can't ask whether a column was renamed, and
  # shows one as a column dropped and another added.
  UNASKED = ->(*) { false } #: ^(Symbol, Symbol, Symbol) -> bool

  # @rbs (directory: String, out: _Writer, kernel: singleton(Kernel), session: Skyward::ORM::Connection::Session,
  #   discover: ^() -> Array[singleton(Skyward::ORM::Record)], generate: ^() -> String?) -> void
  def run(directory:, out:, kernel:, session:, discover:, generate:)
    Skyward::ORM::CLI::BootFile.boot(directory, session, kernel, generate) do |database|
      report(database, directory:, out:, kernel:, discover:)
    end
  end

  private

  # @rbs (Skyward::ORM::Connection::Database database, directory: String, out: _Writer, kernel: singleton(Kernel),
  #   discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def report(database, directory:, out:, kernel:, discover:)
    status = Skyward::ORM::Migrations::Status
    classes = discover.call
    tables = database.tables
    adapter = database.adapter
    migrations = status.migrations(
      Skyward::ORM::Migrations::Runner.read(File.join(directory, Skyward::ORM::Migrations::Directory::PATH)),
      Skyward::ORM::Migrations::Versions.checksums(database)
    )
    changes = Skyward::ORM::Migrations::Diff.changes(classes, database.column_types, tables, adapter, UNASKED)
    unowned = status.unowned(tables, classes)
    out.write(status.text(migrations, changes, unowned, adapter))
    kernel.exit(1) unless status.clean?(migrations, changes, unowned)
  end
end
