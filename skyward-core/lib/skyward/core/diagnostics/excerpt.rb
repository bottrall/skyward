# frozen_string_literal: true

module Skyward::Core::Diagnostics::Excerpt
  extend self

  INDENT = '    ' #: String

  # @rbs spots: Array[Skyward::Core::Diagnostics::Spot]
  # @rbs directory: String
  # @rbs return: String?
  def render(spots, directory: Dir.pwd)
    return if spots.empty?

    spots.group_by(&:path).map { |path, in_file| block(relative(path, directory), in_file) }.join("\n\n")
  end

  private

  # @rbs path: String
  # @rbs spots: Array[Skyward::Core::Diagnostics::Spot]
  # @rbs return: String
  def block(path, spots)
    lines = spots.group_by(&:line).sort_by(&:first)
    texts = lines.map { |(_, on_line)| on_line.fetch(0).text }
    indent = texts.reject { |text| text.strip.empty? }.map { |text| text[/\A\s*/].to_s.size }.min || 0
    header = lines.find { |(_, on_line)| on_line.any?(&:columns) } || lines.fetch(0)
    body = lines.each_with_index.flat_map do |(line, on_line), index|
      gap = '...' if index.positive? && lines.fetch(index - 1).first != line - 1
      [gap, texts.fetch(index)[indent..].to_s, *carets(on_line, indent)].compact
    end
    ["#{path}:#{header.first}", *body].map { |row| "#{INDENT}#{row}".rstrip }.join("\n")
  end

  # @rbs spots: Array[Skyward::Core::Diagnostics::Spot]
  # @rbs indent: Integer
  # @rbs return: Array[String]
  def carets(spots, indent)
    columns = spots.flat_map { |spot| spot.columns.to_a }.map { |column| column - indent }
    return [] if columns.empty?

    [(0..columns.max.to_i).map { |column| columns.include?(column) ? '^' : ' ' }.join]
  end

  # @rbs path: String
  # @rbs directory: String
  # @rbs return: String
  def relative(path, directory)
    prefix = File.join(File.expand_path(directory), '')
    expanded = File.expand_path(path, directory)
    expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : path
  end
end
