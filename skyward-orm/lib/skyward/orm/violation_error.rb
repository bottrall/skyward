# frozen_string_literal: true

class Skyward::ORM::ViolationError < StandardError
  # @dynamic violation
  attr_reader :violation #: Skyward::ORM::Violation

  # @rbs violation: Skyward::ORM::Violation
  # @rbs return: void
  def initialize(violation)
    super(violation.message)
    @violation = violation
  end
end
