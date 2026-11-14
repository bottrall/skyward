# frozen_string_literal: true

# rbs_inline: enabled

module Bench
  # The answer is worked out from a run's result outside the timed loop, so
  # checking a scenario adds nothing to its numbers. A scenario with a unit
  # reports its rate in it: per_iteration of them each iteration.
  Scenario = Data.define(
    :name,           #: String
    :run,            #: ^() -> untyped
    :answer,         #: ^(untyped) -> Hash[Symbol, untyped]
    :expected,       #: Hash[Symbol, untyped]
    :unit,           #: String?
    :per_iteration   #: Integer
  )
end
