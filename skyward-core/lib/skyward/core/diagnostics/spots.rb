# frozen_string_literal: true

require "prism"

module Skyward::Core::Diagnostics::Spots
  extend self

  # @rbs location: RBS::Location[untyped, untyped]
  # @rbs return: Skyward::Core::Diagnostics::Spot
  def rbs(location)
    line = location.start_line
    text = location.buffer.lines.fetch(line - 1, "")
    finish = location.end_line == line ? location.end_column : text.size
    spot(location.buffer.name.to_s, line, text, location.start_column...finish)
  end

  # @rbs method: Method | UnboundMethod
  # @rbs name: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def keyword_parameter(method, name)
    definition(method) { |node| node.parameters&.keywords&.find { |keyword| keyword.name == name }&.location }
  end

  # @rbs method: Method | UnboundMethod
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def parameters(method) = definition(method) { |node| node.parameters&.location }

  # @rbs method: Method | UnboundMethod
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def method_name(method) = definition(method, &:name_loc)

  # @rbs path: String
  # @rbs line: Integer
  # @rbs call: Symbol
  # @rbs key: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def keyword_key(path, line, call:, key:)
    arguments(path, line, call) { |found| pair(found, key)&.key&.location }
  end

  # @rbs path: String
  # @rbs line: Integer
  # @rbs call: Symbol
  # @rbs key: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def keyword_value(path, line, call:, key:)
    arguments(path, line, call) { |found| pair(found, key)&.value&.location }
  end

  # @rbs path: String
  # @rbs line: Integer
  # @rbs call: Symbol
  # @rbs value: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def symbol(path, line, call:, value:)
    arguments(path, line, call) do |found|
      found.find { |argument| symbol?(argument, value) }&.location
    end
  end

  # @rbs path: String
  # @rbs line: Integer
  # @rbs call: Symbol
  # @rbs part: String
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def string(path, line, call:, part:)
    arguments(path, line, call) do |found|
      found.filter_map { |argument| within(argument.content_loc, part) if argument.is_a?(Prism::StringNode) }.first
    end
  end

  # @rbs path: String
  # @rbs line: Integer
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def reader_type(path, line)
    parse(path) do |result|
      next unless call(result, line, :attr_reader)

      comment = result.comments.find do |found|
        found.location.start_line == line && found.location.slice.start_with?("#:")
      end
      within(comment.location, comment.location.slice.delete_prefix("#:").strip) if comment
    end
  end

  private

  # @rbs path: String
  # @rbs line: Integer
  # @rbs text: String
  # @rbs columns: Range[Integer]
  # @rbs return: Skyward::Core::Diagnostics::Spot
  def spot(path, line, text, columns)
    # A zero-width location, such as the end of a file, still gets a caret.
    finish = [columns.end, columns.begin + 1].max
    Skyward::Core::Diagnostics::Spot.new(path:, line:, text:, columns: columns.begin...finish)
  end

  # @rbs path: String
  # @rbs &: (Prism::ParseResult) -> Prism::Location?
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def parse(path)
    return unless File.file?(path)

    source = File.read(path)
    location = yield Prism.parse(source, filepath: path)
    return unless location

    line = location.start_line
    text = source.lines.fetch(line - 1, "").chomp
    finish = location.end_line == line ? location.end_character_column : text.size
    spot(path, line, text, location.start_character_column...finish)
  end

  # @rbs method: Method | UnboundMethod
  # @rbs &: (Prism::DefNode) -> Prism::Location?
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def definition(method)
    path, line = method.source_location
    return unless path && line

    parse(path) do |result|
      found = result.value.breadth_first_search do |node|
        node.is_a?(Prism::DefNode) && node.name == method.original_name && node.location.start_line == line
      end
      yield found if found.is_a?(Prism::DefNode)
    end
  end

  # @rbs path: String
  # @rbs line: Integer
  # @rbs name: Symbol
  # @rbs &: (Array[Prism::node]) -> Prism::Location?
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def arguments(path, line, name)
    parse(path) do |result|
      found = call(result, line, name)
      yield found.arguments&.arguments || [] if found
    end
  end

  # @rbs result: Prism::ParseResult
  # @rbs line: Integer
  # @rbs name: Symbol
  # @rbs return: Prism::CallNode?
  def call(result, line, name)
    found = result.value.breadth_first_search do |node|
      node.is_a?(Prism::CallNode) && node.name == name && node.location.start_line == line
    end
    found if found.is_a?(Prism::CallNode)
  end

  # @rbs arguments: Array[Prism::node]
  # @rbs key: Symbol
  # @rbs return: Prism::AssocNode?
  def pair(arguments, key)
    keywords = arguments.find { |argument| argument.is_a?(Prism::KeywordHashNode) }
    return unless keywords.is_a?(Prism::KeywordHashNode)

    found = keywords.elements.find { |element| element.is_a?(Prism::AssocNode) && symbol?(element.key, key) }
    found if found.is_a?(Prism::AssocNode)
  end

  # @rbs node: Prism::node
  # @rbs value: Symbol
  # @rbs return: bool
  def symbol?(node, value) = node.is_a?(Prism::SymbolNode) && node.unescaped == value.to_s

  # Prism's locations count bytes, so a part is found by its byte offset.
  # @rbs location: Prism::Location
  # @rbs part: String
  # @rbs return: Prism::Location?
  def within(location, part)
    offset = location.slice.byteindex(part)
    location.copy(start_offset: location.start_offset + offset, length: part.bytesize) if offset
  end
end
