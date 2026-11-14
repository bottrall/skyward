# frozen_string_literal: true

require "test_helper"

describe Bench::Runner do
  let(:environment) { { skyward: "0.4.0", sqlite: nil, postgresql: nil } }
  let(:result) { { name: "api.get", ips: 2.0, stddev: 0.5, unit: "requests", rate: 2.0, allocations: 3.0 } }
  let(:said) { [] }
  let(:runs) { [] }
  let(:scenario_names) { %w[api.get api.routes.first orm.sqlite.find_by orm.postgresql.find_by] }

  # Stands in for group.rb: it records each run, writes its results when given
  # an output, and fails the groups it's told to, in the phase it's told to.
  def group(failing: [], phase: :check)
    lambda do |name, names, output|
      runs << [name, names, output && File.basename(output)]
      failed = failing.include?(name) && (phase == (output ? :time : :check))
      unless failed || output.nil?
        File.write(output, JSON.generate({ results: [result.merge(name: "#{name}.x")], versions: { name => "1.0" } }))
      end
      !failed
    end
  end

  def bench(names, postgres_url: nil, run: group)
    Dir.mktmpdir do |scratch|
      Bench::Runner.call(
        names, scenario_names:, postgres_url:, environment:, scratch:, run:, say: ->(line) { said << line }
      )
    end
  end

  describe ".call" do
    it "refuses names no benchmark's starts with" do
      assert_equal "No benchmark's name starts with nope or nah", bench(%w[nope nah])
    end

    it "refuses, before it runs anything, a name no scenario's starts with, though a group's does" do
      assert_equal ["No benchmark's name starts with api.foo", []], [bench(%w[api api.foo]), runs]
    end

    it "says it skips PostgreSQL's group without TEST_POSTGRES_URL" do
      bench(%w[orm])

      assert_equal ["Skipping orm.postgresql: TEST_POSTGRES_URL isn't set"], said
    end

    it "checks every group, then times each, giving each the names" do
      bench(%w[orm api.get], postgres_url: "postgres://localhost/bench")

      assert_equal(
        [
          ["api", "orm,api.get", nil],
          ["orm.sqlite", "orm,api.get", nil],
          ["orm.postgresql", "orm,api.get", nil],
          ["api", "orm,api.get", "api.json"],
          ["orm.sqlite", "orm,api.get", "orm.sqlite.json"],
          ["orm.postgresql", "orm,api.get", "orm.postgresql.json"]
        ],
        runs
      )
    end

    it "times nothing when a check fails" do
      outcome = bench(%w[orm.sqlite api], run: group(failing: %w[api]))

      assert_equal ["A scenario's check failed, so nothing was timed", [nil, nil]], [outcome, runs.map(&:last)]
    end

    it "stops at a group that fails while it's timed" do
      outcome = bench(%w[api orm.sqlite], run: group(failing: %w[api], phase: :time))

      assert_equal ["api failed while it was timed", 3], [outcome, runs.size]
    end

    it "reports every group's results, with its database's version, and what was skipped" do
      report = bench([])

      assert_equal(
        [
          { skyward: "0.4.0", sqlite: nil, postgresql: nil, api: "1.0", "orm.sqlite": "1.0" },
          %w[api.x orm.sqlite.x],
          { "orm.postgresql" => "TEST_POSTGRES_URL isn't set" }
        ],
        [report.environment, report.results.map(&:name), report.skipped]
      )
    end
  end

  describe ".report" do
    it "merges each group's versions into the environment" do
      report = Bench::Runner.report([{ results: [], versions: { sqlite: "3.50.4" } }], environment, {})

      assert_equal({ skyward: "0.4.0", sqlite: "3.50.4", postgresql: nil }, report.environment)
    end
  end
end
