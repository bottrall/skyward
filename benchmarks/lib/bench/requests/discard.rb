# frozen_string_literal: true

# rbs_inline: enabled

# The app's logger: each request still builds its log line, and this drops it.
module Bench::Requests::Discard
  extend self

  # @rbs (String _line) -> void
  def info(_line) = nil
end
