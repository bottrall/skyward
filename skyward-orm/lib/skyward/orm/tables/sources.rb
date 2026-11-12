# frozen_string_literal: true

module Skyward::ORM::Tables::Sources
  extend self

  # @rbs klass: singleton(Skyward::ORM::Record)
  # @rbs declaration: Symbol
  # @rbs name: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def declaration(klass, declaration, name)
    path, line = klass.declared_at(declaration, name)
    return unless path && line

    case declaration
    when :default then Skyward::Core::Diagnostics::Spots.keyword_key(path, line, call: :default, key: name)
    else Skyward::Core::Diagnostics::Spots.symbol(path, line, call: declaration, value: name)
    end
  end

  # A type in a hand-written .rbs leaves the reader's line with no type to
  # point at, so the carets go under the column's name.
  # @rbs klass: Class
  # @rbs column: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def reader(klass, column)
    return unless klass <= Skyward::ORM::Record

    table = klass #: singleton(Skyward::ORM::Record)
    path, line = table.declared_at(:attr_reader, column)
    return unless path && line

    Skyward::Core::Diagnostics::Spots.reader_type(path, line) ||
      Skyward::Core::Diagnostics::Spots.symbol(path, line, call: :attr_reader, value: column)
  end

  # Only a `class` keyword's line is pointed at, so a class from Class.new
  # keeps its message even once a constant names it, as its declarations do.
  # @rbs klass: Module
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def class_name(klass)
    name = klass.name
    # A class in an anonymous module has a temporary name, which const_source_location refuses.
    path, line = Object.const_source_location(name) if name && !name.start_with?("#<")
    return unless name && path && line && File.file?(path)

    text = File.readlines(path).fetch(line - 1, "").chomp
    start, finish = text.match(/\bclass\s+\K(?:\w+::)*#{Regexp.escape(name.split("::").last.to_s)}\b/)&.offset(0)
    Skyward::Core::Diagnostics::Spot.new(path:, line:, text:, columns: start...finish) if start && finish
  end

  # @rbs message: String
  # @rbs spots: Array[Skyward::Core::Diagnostics::Spot?]
  # @rbs suggestion: String?
  # @rbs return: String
  def explain(message, spots, suggestion = nil)
    hint = "Did you mean #{suggestion}?" if suggestion
    [[message, Skyward::Core::Diagnostics::Excerpt.render(spots.compact)].compact.join("\n\n"), hint].compact.join("\n")
  end

  # @rbs problems: Array[String]
  # @rbs return: String
  def join(problems) = problems.join(problems.any? { |problem| problem.include?("\n") } ? "\n\n" : "\n")
end
