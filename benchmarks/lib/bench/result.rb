# frozen_string_literal: true

# rbs_inline: enabled

module Bench
  # ips and stddev are iterations per second. rate is ips in the scenario's
  # unit, when it has one, and allocations are objects per iteration.
  Result = Data.define(
    :name,         #: String
    :ips,          #: Float
    :stddev,       #: Float
    :unit,         #: String?
    :rate,         #: Float?
    :allocations   #: Float
  )
end
