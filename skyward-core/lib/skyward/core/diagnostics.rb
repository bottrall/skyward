# frozen_string_literal: true

module Skyward::Core::Diagnostics
  # The line's text travels with it, so an excerpt never reads the file again.
  Spot = Data.define(
    :path, #: String
    :line, #: Integer
    :text, #: String
    :columns #: Range[Integer]?
  )
end
