# frozen_string_literal: true

class Skyward::Unprocessable
  # @dynamic detail
  attr_reader :detail #: String

  # @dynamic headers
  attr_reader :headers #: Hash[String, String]

  # @rbs detail: String
  # @rbs headers: Hash[String, String]
  # @rbs return: void
  def initialize(detail:, headers:)
    @detail = detail
    @headers = headers
    freeze
  end
end
