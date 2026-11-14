# frozen_string_literal: true

# rbs_inline: enabled

# Writes a run's report as JSON, and as Markdown for a PR's Proof or a
# release.
module Bench::Results
  extend self

  ENVIRONMENT = {
    skyward: 'Skyward',
    commit: 'Commit',
    ruby: 'Ruby',
    yjit: 'YJIT',
    cpu: 'CPU',
    sqlite: 'SQLite',
    postgresql: 'PostgreSQL'
  }.freeze #: Hash[Symbol, String]

  # @rbs report: Bench::Report
  # @rbs directory: String
  # @rbs return: void
  def write(report, directory)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'results.json'), json(report))
    File.write(File.join(directory, 'results.md'), markdown(report))
  end

  # @rbs report: Bench::Report
  # @rbs return: String
  def json(report)
    document = { environment: report.environment, results: report.results.map(&:to_h), skipped: report.skipped }
    "#{JSON.pretty_generate(document)}\n"
  end

  # @rbs report: Bench::Report
  # @rbs return: String
  def markdown(report)
    results = report.results.map { |result| row(result) }
    skipped = report.skipped.map { |group, reason| "#{group} was skipped: #{reason}.\n\n" }
    environment = ENVIRONMENT.map { |key, label| "| #{label} | #{value(report.environment[key])} |" }
    <<~MARKDOWN
      | Scenario | Iterations/s | ± | Rate | Objects/iteration |
      | --- | ---: | ---: | ---: | ---: |
      #{results.join("\n")}

      #{skipped.join}| Environment | |
      | --- | --- |
      #{environment.join("\n")}
    MARKDOWN
  end

  # @rbs result: Bench::Result
  # @rbs return: String
  def row(result)
    rate = result.rate
    throughput = rate ? "#{number(rate, 0)} #{result.unit}/s" : '—'
    deviation = number(result.stddev / result.ips * 100, 1)
    "| #{result.name} | #{number(result.ips, 1)} | #{deviation}% | #{throughput} | #{number(result.allocations, 1)} |"
  end

  # @rbs value: untyped
  # @rbs return: String
  def value(value)
    case value
    when nil then '—'
    when true then 'on'
    when false then 'off'
    else value.to_s
    end
  end

  # @rbs value: Float
  # @rbs digits: Integer
  # @rbs return: String
  def number(value, digits)
    format("%.#{digits}f", value).sub(/\A\d+/) { |whole| whole.reverse.scan(/\d{1,3}/).join(',').reverse }
  end
end
