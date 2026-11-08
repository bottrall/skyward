# frozen_string_literal: true

module Skyward::API::Routes
  extend self

  GAP = 2 #: Integer

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs return: String
  def table(endpoints)
    rows = endpoints.map do |endpoint|
      [endpoint.verb, path(endpoint.pattern), handler(endpoint), endpoint.signature.gsub(/\s*\R\s*/, " ")]
    end
    widths = rows.transpose.map { |column| (column.map(&:length).max || 0) + GAP }
    rows.map do |row|
      *padded, signature = row
      "#{padded.map.with_index { |cell, index| cell.ljust(widths.fetch(index)) }.join}#{signature}\n"
    end.join
  end

  private

  # @rbs pattern: Array[String | Symbol]
  # @rbs return: String
  def path(pattern) = pattern.map { |part| part.is_a?(Symbol) ? ":#{part}" : part }.join("/")

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: String
  def handler(endpoint) = "#{endpoint.api.class}##{endpoint.to}"
end
