# frozen_string_literal: true

# rbs_inline: enabled

module Bench::Measure
  extend self

  ALLOCATION_ITERATIONS = 1_000 #: Integer

  # Runs each scenario once, so a benchmark never times a 500 or an empty
  # result.
  # @rbs scenarios: Array[Bench::Scenario]
  # @rbs return: Array[String]
  def failures(scenarios)
    scenarios.filter_map do |scenario|
      answer = scenario.answer.call(scenario.run.call)
      "#{scenario.name} answered #{answer}, not #{scenario.expected}" unless answer == scenario.expected
    end
  end

  # benchmark-ips prints its report as it goes, unless quiet.
  # @rbs scenarios: Array[Bench::Scenario]
  # @rbs time: Numeric
  # @rbs warmup: Numeric
  # @rbs quiet: bool
  # @rbs return: Array[Bench::Result]
  def results(scenarios, time: 5, warmup: 2, quiet: false)
    report = Benchmark.ips(time:, warmup:, quiet:) do |job|
      scenarios.each { |scenario| job.report(scenario.name) { scenario.run.call } }
    end
    entries = report.entries.to_h { |entry| [entry.label, entry] }
    scenarios.map { |scenario| result(scenario, entries.fetch(scenario.name)) }
  end

  # @rbs scenario: Bench::Scenario
  # @rbs entry: Benchmark::IPS::Report::Entry
  # @rbs return: Bench::Result
  def result(scenario, entry)
    Bench::Result.new(
      name: scenario.name,
      ips: entry.ips,
      stddev: entry.ips_sd.to_f,
      unit: scenario.unit,
      rate: scenario.unit ? entry.ips * scenario.per_iteration : nil,
      allocations: allocations(scenario.run)
    )
  end

  # Counted after benchmark-ips has warmed the scenario up, so what its first
  # run allocates once, such as a cached statement, isn't counted.
  # @rbs run: ^() -> untyped
  # @rbs return: Float
  def allocations(run)
    before = GC.stat(:total_allocated_objects)
    ALLOCATION_ITERATIONS.times { run.call }
    (GC.stat(:total_allocated_objects) - before).fdiv(ALLOCATION_ITERATIONS)
  end
end
