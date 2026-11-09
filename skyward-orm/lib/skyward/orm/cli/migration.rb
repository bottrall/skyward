# frozen_string_literal: true

module Skyward::ORM::CLI::Migration
  extend self

  NAME = /\A[A-Za-z0-9_]+\z/ #: Regexp

  EMPTY = "--empty" #: String

  USAGE = "Usage: skyward migration [--empty] NAME\n" \
          "NAME is letters, digits and _, such as add_notes_to_todos.\n" \
          "--empty writes an empty migration for SQL you write yourself." #: String

  NOTHING = "Every table matches its class. Nothing to write.\n" #: String

  YES = /\Ay(?:es)?\z/i #: Regexp

  # @rbs (Array[String] args, directory: String, time: Time, input: IO, out: _Writer, kernel: singleton(Kernel),
  #   session: Skyward::ORM::Connection::Session, discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def run(args, directory:, time:, input:, out:, kernel:, session:, discover:)
    flags, names = args.partition { |arg| arg.start_with?("-") }
    name = names.fetch(0) if names.one?
    empty = flags == [EMPTY]
    return kernel.abort(USAGE) unless name&.match?(NAME) && (empty || flags.empty?)

    taken = Skyward::ORM::Migrations::Directory.named(directory, name)
    return kernel.abort("skyward: #{taken} is already named #{name}. Choose another name.") if taken
    # An empty migration compares nothing, so it skips booting and works before
    # the app can connect.
    return write_empty(name, directory:, time:, out:) if empty

    Skyward::ORM::CLI::BootFile.boot(directory, session, kernel) do |database|
      write(name, database, directory:, time:, input:, out:, kernel:, discover:)
    end
  end

  private

  # @rbs (String name, directory: String, time: Time, out: _Writer) -> void
  def write_empty(name, directory:, time:, out:)
    file = Skyward::ORM::Migrations::Directory.write(directory, time, name, "\n-- down\n")
    out.write("Wrote #{file}. Add your SQL, then run `skyward migrate`.\n")
  end

  # Writing a second migration before the first has run would write the same
  # change twice, so a pending one stops it. With no terminal to ask whether a
  # column was renamed, it stops rather than guess, since a guess of no drops
  # the column's data.
  # @rbs (String name, Skyward::ORM::Connection::Database database, directory: String, time: Time, input: IO,
  #   out: _Writer, kernel: singleton(Kernel), discover: ^() -> Array[singleton(Skyward::ORM::Record)]) -> void
  def write(name, database, directory:, time:, input:, out:, kernel:, discover:)
    ran = Skyward::ORM::Migrations::Versions.checksums(database).keys
    pending = Skyward::ORM::Migrations::Directory.pending(directory, ran)
    return kernel.abort(pending(pending)) unless pending.empty?

    adapter = database.adapter
    unasked = [] #: Array[String]
    rename = if input.tty?
               ->(table, from, to) { renamed?(input, out, "Did you rename #{table}.#{from} to #{table}.#{to}? [y/N] ") }
             else
               lambda do |table, from, to|
                 unasked.push("#{table}.#{from} to #{table}.#{to}")
                 false
               end
             end
    changes = Skyward::ORM::Migrations::Diff.changes(
      discover.call,
      database.column_types,
      database.tables,
      adapter,
      rename
    )
    return kernel.abort(unasked(unasked)) unless unasked.empty?
    return out.write(NOTHING) if changes.empty?

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

  # @rbs input: IO
  # @rbs out: _Writer
  # @rbs question: String
  # @rbs return: bool
  def renamed?(input, out, question)
    out.write(question)
    input.gets.to_s.strip.match?(YES)
  end

  # @rbs renames: Array[String]
  # @rbs return: String
  def unasked(renames)
    "skyward: did you rename #{renames.join(", or ")}? There's no terminal to ask, so nothing was written. " \
      "Run `skyward migration` in a terminal to answer."
  end

  # @rbs files: Array[String]
  # @rbs return: String
  def pending(files)
    "skyward: #{files.join(", ")} #{files.one? ? "hasn't" : "haven't"} run yet. " \
      "Run `skyward migrate` before writing the next migration."
  end
end
