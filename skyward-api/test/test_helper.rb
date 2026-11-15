# frozen_string_literal: true

require 'minitest/autorun'
require 'skyward/api'

module Minitest::Assertions
  # message is the String the error's message equals, or a Regexp it matches.
  def assert_raises_with_message(klass, message, &)
    error = assert_raises(klass, &)
    message.is_a?(Regexp) ? assert_match(message, error.message) : assert_equal(message, error.message)
  end
end
