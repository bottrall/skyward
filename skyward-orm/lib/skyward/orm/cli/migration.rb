# frozen_string_literal: true

module Skyward::ORM::CLI::Migration
  extend self

  NAME = /\A[A-Za-z0-9_]+\z/ #: Regexp

  USAGE = "Usage: skyward migration NAME\n" \
          "NAME is letters, digits and _, such as add_notes_to_todos." #: String

  NOTHING = "Every table matches its class. Nothing to write.\n" #: String

  # @rbs (Array[String] args, directory: String, time: Time, out: _Writer, kernel: singleton(Kernel),
  #   session: Skyward::ORM::Connection::Session, discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def run(args, directory:, time:, out:, kernel:, session:, discover:)
    name = args.fetch(0) if args.one?
    return kernel.abort(USAGE) unless name&.match?(NAME)

    taken = Skyward::ORM::Migrations::Directory.named(directory, name)
    return kernel.abort("skyward: #{taken} is already named #{name}. Choose another name.") if taken

    database = session.without_check { Skyward::ORM::CLI::BootFile.load(directory, session) }
    case database
    when String then kernel.abort(database)
    else write(name, database, directory:, time:, out:, kernel:, discover:)
    end
  # Booting the app raises it, and so does a table class that can't be migrated.
  rescue Skyward::Core::BootError => e
    kernel.abort(e.message)
  end

  private

  # Writing a second migration before the first has run would write the same
  # change twice, so a pending one stops it.
  # @rbs (String name, Skyward::ORM::Connection::Database database, directory: String, time: Time, out: _Writer,
  #   kernel: singleton(Kernel), discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def write(name, database, directory:, time:, out:, kernel:, discover:)
    ran = Skyward::ORM::Migrations::Versions.ran(database)
    pending = Skyward::ORM::Migrations::Directory.pending(directory, ran)
    return kernel.abort(pending(pending)) unless pending.empty?

    changes = Skyward::ORM::Migrations::Diff.changes(discover.call, database.column_types, database.tables)
    return out.write(NOTHING) if changes.empty?

    adapter = database.adapter
    file = Skyward::ORM::Migrations::Directory.write(
      directory,
      time,
      name,
      Skyward::ORM::Migrations::Script.write(changes, adapter)
    )
    out.write(
      Skyward::ORM::Migrations::Summary.text(changes, adapter),
      "Wrote #{file}. Review it, then run `skyward migrate`.\n"
    )
  end

  # @rbs files: Array[String]
  # @rbs return: String
  def pending(files)
    "skyward: #{files.join(", ")} #{files.one? ? "hasn't" : "haven't"} run yet. " \
      "Run `skyward migrate` before writing the next migration."
  end
end
