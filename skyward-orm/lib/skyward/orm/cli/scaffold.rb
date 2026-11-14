# frozen_string_literal: true

module Skyward::ORM::CLI::Scaffold
  extend self

  USAGE = <<~TEXT.chomp #: String
    Usage: skyward scaffold TABLE
    Prints a table class for TABLE, to save where your app keeps its classes:
      skyward scaffold todos > app/todo.rb
  TEXT

  # A row compiles @name for each column, and has these methods of its own.
  COLUMN = /\A[a-z_][a-z0-9_]*\z/ #: Regexp
  TAKEN = [*Skyward::ORM::Tables::Rows::METHODS, :with, :members].freeze #: Array[Symbol]

  # @rbs (Array[String] args, directory: String, out: _Writer, kernel: singleton(Kernel),
  #   session: Skyward::ORM::Connection::Session, discover: ^() -> Array[singleton(Skyward::ORM::Record)],
  #   generate: ^() -> String?) -> void
  def run(args, directory:, out:, kernel:, session:, discover:, generate:)
    name = args.fetch(0) if args.one?
    return kernel.abort(USAGE) if name.nil? || name.start_with?('-')

    Skyward::ORM::CLI::BootFile.boot(directory, session, kernel, generate) do |database|
      classes = discover.call
      tables = database.tables
      found = find(name, tables, classes)
      case found
      when String then kernel.abort(found)
      else out.write(Skyward::ORM::CLI::Scaffold::Source.text(found, tables, database.adapter, classes))
      end
    end
  end

  private

  # @rbs name: String
  # @rbs tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: Skyward::ORM::Catalog::Table | String
  def find(name, tables, classes)
    table = tables.find { |candidate| candidate.name.name == name }
    return refusal(table, classes) || table if table

    suggestion = DidYouMean::SpellChecker.new(dictionary: tables.map { |candidate| candidate.name.name })
                                         .correct(name).first
    "skyward: there's no table #{name}.#{" Did you mean #{suggestion}?" if suggestion}"
  end

  # @rbs table: Skyward::ORM::Catalog::Table
  # @rbs classes: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: String?
  def refusal(table, classes)
    name = table.name
    owner = classes.find { |klass| klass.table_name == name }
    key = Skyward::ORM::CLI::Scaffold::Source.primary_key(table)
    unreadable = table.columns.map(&:name).reject { |column| column.match?(COLUMN) && !TAKEN.include?(column) }
    if name == Skyward::ORM::Migrations::Versions::TABLE
      "skyward: #{name} is Skyward ORM's own table, so it needs no class."
    elsif owner then "skyward: #{owner} already declares table :#{name}."
    elsif !key.one?
      "skyward: #{name} has #{key.empty? ? 'no primary key' : "a primary key on (#{key.join(', ')})"}, and a table " \
        'class has a one-column primary key. Give the table one in a `skyward migration --empty` migration, then ' \
        'scaffold it.'
    elsif !unreadable.empty?
      "skyward: a table class reads each column as a lowercase Ruby method a row doesn't already have, so it can't " \
        "read #{unreadable.map { |column| "#{name}.#{column}" }.join(' or ')}. Rename each in a " \
        '`skyward migration --empty` migration, then scaffold it.'
    end
  end
end
