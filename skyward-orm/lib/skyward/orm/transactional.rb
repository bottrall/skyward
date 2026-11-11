# frozen_string_literal: true

# @rbs module-self Minitest::Test::LifecycleHooks
module Skyward::ORM::Transactional
  # @rbs return: void
  def before_setup
    Skyward::ORM::Connection::SESSION.hold
    super
  end

  # Minitest calls this even when setup or the test raised.
  # @rbs return: void
  def after_teardown
    super
  ensure
    Skyward::ORM::Connection::SESSION.release
  end
end
