# frozen_string_literal: true

module Minitest::Assertions
  # message is the String the error's message equals, or a Regexp it matches.
  def assert_raises_with_message(klass, message, &)
    error = assert_raises(klass, &)
    message.is_a?(Regexp) ? assert_match(message, error.message) : assert_equal(message, error.message)
  end

  def assert_raises_with_violation(violation, &)
    assert_equal violation, assert_raises(Skyward::ORM::ViolationError, &).violation
  end
end
