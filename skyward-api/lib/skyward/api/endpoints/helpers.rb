# frozen_string_literal: true

# Private, so a route can't name a helper as its method.
module Skyward::API::Endpoints::Helpers
  private

  # @rbs [T] (T value, ?headers: Hash[String, String]) -> Skyward::API::Responses::Created[T]
  def created(value, headers: {}) = Skyward::API::Responses::Created.new(value:, headers:)

  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::NoContent
  def no_content(headers: {}) = Skyward::API::Responses::NoContent.new(headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::BadRequest
  def bad_request(detail, headers: {}) = Skyward.bad_request(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::Unauthorized
  def unauthorized(detail, headers: {}) = Skyward.unauthorized(detail, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::Forbidden
  def forbidden(detail, headers: {}) = Skyward.forbidden(detail, headers:)

  # @rbs detail: String?
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::NotFound
  def not_found(detail = nil, headers: {}) = Skyward::API::Responses::NotFound.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::Conflict
  def conflict(detail, headers: {}) = Skyward::API::Responses::Conflict.new(detail:, headers:)

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::Unprocessable
  def unprocessable(detail, headers: {}) = Skyward::API::Responses::Unprocessable.new(detail:, headers:)

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: Skyward::API::Responses::Redirect
  def redirect(to, status: 303, headers: {}) = Skyward.redirect(to, status:, headers:)
end
