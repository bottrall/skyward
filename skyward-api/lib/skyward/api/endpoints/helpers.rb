# frozen_string_literal: true

# Private, so a route can't name a helper as its method.
module Skyward::API::Endpoints::Helpers
  private

  # @rbs [T] (T value, ?headers: Hash[String, String]) -> Skyward::Responses::Created[T]
  def created(value, headers: {}) = Skyward::Responses::Created.new(value:, headers:)

  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::NoContent
  def no_content(headers: {}) = Skyward::Responses::NoContent.new(headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::BadRequest
  def bad_request(detail, headers: {}) = Skyward.bad_request(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::Unauthorized
  def unauthorized(detail, headers: {}) = Skyward.unauthorized(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::Forbidden
  def forbidden(detail, headers: {}) = Skyward.forbidden(detail, headers:)

  # @rbs detail: String?
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::NotFound
  def not_found(detail = nil, headers: {}) = Skyward::Responses::NotFound.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::Conflict
  def conflict(detail, headers: {}) = Skyward::Responses::Conflict.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::Unprocessable
  def unprocessable(detail, headers: {}) = Skyward::Responses::Unprocessable.new(detail:, headers:)

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::Responses::Redirect
  def redirect(to, status: 303, headers: {}) = Skyward.redirect(to, status:, headers:)
end
