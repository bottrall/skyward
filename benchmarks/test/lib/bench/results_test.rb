# frozen_string_literal: true

require 'test_helper'

describe Bench::Results do
  results = Bench::Results

  let(:get) { Bench::Result.new(name: 'api.get', ips: 41_234.56, stddev: 824.69, unit: 'requests', rate: 41_234.56, allocations: 37.0) }
  let(:build) { Bench::Result.new(name: 'orm.sqlite.build', ips: 1_000.0, stddev: 10.0, unit: nil, rate: nil, allocations: 12.5) }
  let(:environment) do
    {
      skyward: '0.4.0',
      commit: 'abc123',
      ruby: 'ruby 4.0.0 +YJIT',
      yjit: true,
      cpu: nil,
      sqlite: '3.50.4',
      postgresql: nil
    }
  end
  let(:report) do
    Bench::Report.new(
      environment:,
      results: [get, build],
      skipped: { 'orm.postgresql' => "TEST_POSTGRES_URL isn't set" }
    )
  end

  describe '.write' do
    it 'writes the report as JSON and as Markdown' do
      Dir.mktmpdir do |dir|
        directory = File.join(dir, 'tmp/bench')
        results.write(report, directory)

        assert_equal(
          [results.json(report), results.markdown(report)],
          %w[results.json results.md].map { |file| File.read(File.join(directory, file)) }
        )
      end
    end
  end

  describe '.json' do
    it 'holds the environment, each result and each group skipped' do
      assert_equal(
        {
          environment: environment,
          results: [get.to_h, build.to_h],
          skipped: { 'orm.postgresql': "TEST_POSTGRES_URL isn't set" }
        },
        JSON.parse(results.json(report), symbolize_names: true)
      )
    end
  end

  describe '.markdown' do
    it 'tables the results, says what was skipped, and tables the environment' do
      assert_equal <<~MARKDOWN, results.markdown(report)
        | Scenario | Iterations/s | ± | Rate | Objects/iteration |
        | --- | ---: | ---: | ---: | ---: |
        | api.get | 41,234.6 | 2.0% | 41,235 requests/s | 37.0 |
        | orm.sqlite.build | 1,000.0 | 1.0% | — | 12.5 |

        orm.postgresql was skipped: TEST_POSTGRES_URL isn't set.

        | Environment | |
        | --- | --- |
        | Skyward | 0.4.0 |
        | Commit | abc123 |
        | Ruby | ruby 4.0.0 +YJIT |
        | YJIT | on |
        | CPU | — |
        | SQLite | 3.50.4 |
        | PostgreSQL | — |
      MARKDOWN
    end

    it 'says nothing was skipped when nothing was' do
      refute_includes results.markdown(report.with(skipped: {})), 'skipped'
    end
  end

  describe '.row' do
    it "reports the rate in the scenario's unit" do
      assert_includes results.row(get), '| 41,235 requests/s |'
    end

    it 'reports no rate without a unit' do
      assert_includes results.row(build), '| — |'
    end
  end

  describe '.value' do
    it 'writes nothing known as a dash' do
      assert_equal '—', results.value(nil)
    end

    it 'writes true as on' do
      assert_equal 'on', results.value(true)
    end

    it 'writes false as off' do
      assert_equal 'off', results.value(false)
    end

    it 'writes anything else as it is' do
      assert_equal '3.50.4', results.value('3.50.4')
    end
  end

  describe '.number' do
    it 'groups the thousands' do
      assert_equal '1,234,567.9', results.number(1_234_567.89, 1)
    end

    it 'rounds to the digits given' do
      assert_equal '1,235', results.number(1_234.6, 0)
    end

    it 'leaves a number under a thousand ungrouped' do
      assert_equal '999.0', results.number(999.0, 1)
    end
  end
end
