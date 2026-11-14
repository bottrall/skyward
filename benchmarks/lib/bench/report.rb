# frozen_string_literal: true

# rbs_inline: enabled

module Bench
  # skipped holds each group that didn't run, and why.
  Report = Data.define(
    :environment,  #: Hash[Symbol, untyped]
    :results,      #: Array[Bench::Result]
    :skipped       #: Hash[String, String]
  )
end
