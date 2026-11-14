# frozen_string_literal: true

require "test_helper"

describe Bench::Measure do
  measure = Bench::Measure

  def scenario(name, answer: 1, unit: nil, per_iteration: 1)
    Bench::Scenario.new(
      name:,
      run: -> { answer },
      answer: ->(value) { { value: } },
      expected: { value: 1 },
      unit:,
      per_iteration:
    )
  end

  def results(*scenarios) = Bench::Measure.results(scenarios, time: 0.01, warmup: 0.01, quiet: true)

  describe ".failures" do
    it "finds none when every answer is the one expected" do
      assert_empty measure.failures([scenario("x")])
    end

    it "names each scenario whose answer isn't, and what it answered" do
      answered = { value: 2 }
      expected = { value: 1 }

      failures = measure.failures([scenario("x"), scenario("y", answer: 2)])

      assert_equal ["y answered #{answered}, not #{expected}"], failures
    end
  end

  describe ".results" do
    it "times each scenario, in order" do
      assert_equal %w[x y], results(scenario("x"), scenario("y")).map(&:name)
    end

    it "reports iterations per second" do
      assert_operator results(scenario("x")).fetch(0).ips, :>, 0
    end
  end

  describe ".result" do
    it "reports the rate in the scenario's unit" do
      result = results(scenario("x", unit: "rows", per_iteration: 100)).fetch(0)

      assert_equal ["rows", result.ips * 100], [result.unit, result.rate]
    end

    it "reports no rate without a unit" do
      assert_nil results(scenario("x")).fetch(0).rate
    end
  end

  describe ".allocations" do
    it "counts the objects each run allocates" do
      assert_in_delta 2.0, measure.allocations(-> { [Object.new] }), 0.01
    end

    it "counts none for a run that allocates nothing" do
      assert_in_delta 0.0, measure.allocations(-> { 1 }), 0.01
    end
  end
end
