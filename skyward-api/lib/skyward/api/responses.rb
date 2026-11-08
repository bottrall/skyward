# frozen_string_literal: true

# Private, so a route can't name a helper as its method.
module Skyward::API::Responses
  private

  # @rbs [T] (T value, ?headers: Hash[String, String]) -> Skyward::Created[T]
  def created(value, headers: {}) = Skyward::Created.new(value:, headers:)

  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::NoContent
  def no_content(headers: {}) = Skyward::NoContent.new(headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::BadRequest
  def bad_request(detail, headers: {}) = Skyward.bad_request(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Unauthorized
  def unauthorized(detail, headers: {}) = Skyward.unauthorized(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Forbidden
  def forbidden(detail, headers: {}) = Skyward.forbidden(detail, headers:)

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

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Redirect
  def redirect(to, status: 303, headers: {}) = Skyward.redirect(to, status:, headers:)
end
