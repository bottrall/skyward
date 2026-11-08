# frozen_string_literal: true

# @rbs generic out T
class Skyward::Created
  # @dynamic value
  attr_reader :value #: T

  # @dynamic headers
  attr_reader :headers #: Hash[String, String]

  # @rbs value: T
  # @rbs headers: Hash[String, String]
  # @rbs return: void
  def initialize(value:, headers:)
    @value = value
    @headers = headers
    freeze
  end
end
