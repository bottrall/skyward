# frozen_string_literal: true

class Skyward::API::Responses::NoContent
  # @dynamic headers
  attr_reader :headers #: Hash[String, String]

  # @rbs headers: Hash[String, String]
  # @rbs return: void
  def initialize(headers:)
    @headers = headers
    freeze
  end
end
