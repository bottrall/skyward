# frozen_string_literal: true

class Skyward::Redirect
  STATUSES = [301, 302, 303, 307, 308].freeze #: Array[Integer]

  # @dynamic to
  attr_reader :to #: String

  # @dynamic status
  attr_reader :status #: Integer

  # @dynamic headers
  attr_reader :headers #: Hash[String, String]

  # @rbs to: String
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: void
  def initialize(to:, status:, headers:)
    @to = to
    @status = status
    @headers = headers
    freeze
  end
end
