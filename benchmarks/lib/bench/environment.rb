# frozen_string_literal: true

# rbs_inline: enabled

# What a run's numbers depend on. Each database's version comes from the group
# that connects to it, and stays nil when that group doesn't run.
module Bench::Environment
  extend self

  # @rbs commit: String
  # @rbs ruby: String
  # @rbs cpuinfo: String?
  # @rbs return: Hash[Symbol, untyped]
  def describe(commit:, ruby:, cpuinfo:)
    {
      skyward: Skyward::Core::VERSION,
      commit:,
      ruby:,
      # Ruby adds +YJIT to its description once YJIT is on, however it was
      # turned on.
      yjit: ruby.include?('+YJIT'),
      cpu: cpuinfo&.slice(/^model name\s*:\s*(.+)$/, 1),
      sqlite: nil,
      postgresql: nil
    }
  end
end
