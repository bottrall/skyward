# frozen_string_literal: true

# Private, so a route can't name a helper as its method.
module Skyward::API::Responses
  private

  # @rbs [T] (T value, ?headers: Hash[String, String]) -> Skyward::Created[T]
  def created(value, headers: {}) = Skyward::Created.new(value:, headers:)

  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::NoContent
  def no_content(headers: {}) = Skyward::NoContent.new(headers:)

  # @rbs detail: String?
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::NotFound
  def not_found(detail = nil, headers: {}) = Skyward::NotFound.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Conflict
  def conflict(detail, headers: {}) = Skyward::Conflict.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Unprocessable
  def unprocessable(detail, headers: {}) = Skyward::Unprocessable.new(detail:, headers:)
end
