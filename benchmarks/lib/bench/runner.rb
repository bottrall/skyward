# frozen_string_literal: true

# rbs_inline: enabled

module Bench::Runner
  extend self

  # run takes a group, the names it's given, comma-separated, and the path to
  # write its results to, or nil to only check them, and answers whether it
  # succeeded.
  # @rbs names: Array[String]
  # @rbs scenario_names: Array[String]
  # @rbs postgres_url: String?
  # @rbs environment: Hash[Symbol, untyped]
  # @rbs scratch: String
  # @rbs run: ^(String, String, String?) -> bool
  # @rbs say: ^(String) -> void
  # @rbs return: Bench::Report | String
  def call(names, scenario_names:, postgres_url:, environment:, scratch:, run:, say:)
    unmatched = Bench::Groups.unmatched(names, scenario_names)
    return "No benchmark's name starts with #{unmatched.join(' or ')}" unless unmatched.empty?

    groups = Bench::Groups.selected(names)
    skipped = Bench::Groups.skipped(groups, postgres_url)
    skipped.each { |group, reason| say.call("Skipping #{group}: #{reason}") }
    running = groups - skipped.keys
    joined = names.join(',')
    # Every check runs, and all of them pass, before anything is timed.
    checked = running.map { |group| run.call(group, joined, nil) }
    return "A scenario's check failed, so nothing was timed" unless checked.all?

    outputs = running.map do |group|
      output = File.join(scratch, "#{group}.json")
      return "#{group} failed while it was timed" unless run.call(group, joined, output)

      JSON.parse(File.read(output), symbolize_names: true)
    end
    report(outputs, environment, skipped)
  end

  # @rbs outputs: Array[Hash[Symbol, untyped]]
  # @rbs environment: Hash[Symbol, untyped]
  # @rbs skipped: Hash[String, String]
  # @rbs return: Bench::Report
  def report(outputs, environment, skipped)
    results = outputs.flat_map { |output| output.fetch(:results) } #: Array[Hash[Symbol, untyped]]
    Bench::Report.new(
      environment: environment.merge(*outputs.map { |output| output.fetch(:versions) }),
      # Steep can't match a Hash's splat to a Data's required keywords.
      results: results.map { |result| Bench::Result.new(**result) }, # steep:ignore UnresolvedOverloading
      skipped:
    )
  end
end
