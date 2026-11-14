# frozen_string_literal: true

require 'test_helper'

describe Bench::Queries do
  queries = Bench::Queries
  postgresql = File.join(Bench::Queries::MIGRATIONS, 'postgresql')

  def on_postgresql(&)
    skip 'Set TEST_POSTGRES_URL to run the PostgreSQL scenarios' unless POSTGRES
    Skyward.using(POSTGRES, &)
  end

  def table?(name) = !Skyward.query('SELECT to_regclass(?)::text AS name', name).fetch(0).fetch(:name).nil?

  def answers(scenarios) = scenarios.map { |scenario| scenario.answer.call(scenario.run.call) }

  describe '.prepare' do
    it 'seeds the rows on SQLite' do
      assert_equal [1_000, 1], [Bench::Task.all.count, Bench::Task.all.order(:id).first.id]
    end

    it "starts PostgreSQL's table again each time" do
      on_postgresql do
        2.times { queries.prepare('postgresql') }

        assert_equal [1_000, 1], [Bench::Task.all.count, Bench::Task.all.order(:id).first.id]
      end
    end
  end

  describe '.forget' do
    it 'drops the table' do
      on_postgresql do
        queries.forget(postgresql)

        refute table?('bench_tasks')
      ensure
        queries.prepare('postgresql')
      end
    end

    it "drops only the table on a database that's never been migrated" do
      on_postgresql do
        Skyward.query('DROP TABLE schema_migrations')
        queries.forget(postgresql)

        refute table?('schema_migrations')
      ensure
        queries.prepare('postgresql')
      end
    end
  end

  describe '.rows' do
    it "numbers each row's title" do
      assert_equal(['Task 1', 'Task 2'], queries.rows(2).map { |row| row.fetch(:title) })
    end

    it 'leaves every fourth row with no due date' do
      assert_equal([false, false, false, true], queries.rows(4).map { |row| row.fetch(:due_on).nil? })
    end
  end

  describe '.version' do
    it "answers SQLite's version" do
      assert_match(/\A3\.\d+\.\d+\z/, queries.version('sqlite'))
    end

    it "answers PostgreSQL's server version" do
      on_postgresql { assert_match(/\A\d+\.\d+/, queries.version('postgresql')) }
    end
  end

  describe '.scenarios' do
    it "names the group's scenarios" do
      assert_equal %w[x.rows.1 x.rows.100 x.rows.1000 x.find_by x.build], queries.scenarios('x').map(&:name)
    end

    it "gets each scenario's expected answer from SQLite" do
      scenarios = queries.scenarios('orm.sqlite')

      assert_equal scenarios.map(&:expected), answers(scenarios)
    end

    it "gets each scenario's expected answer from PostgreSQL" do
      scenarios = queries.scenarios('orm.postgresql')

      on_postgresql { assert_equal scenarios.map(&:expected), answers(scenarios) }
    end
  end

  describe '.rows_scenario' do
    it 'reports rows, as many as it reads each time' do
      scenario = queries.rows_scenario('x', 100)

      assert_equal ['rows', 100], [scenario.unit, scenario.per_iteration]
    end
  end

  describe '.summary' do
    it 'answers no first id for no rows' do
      assert_equal({ rows: 0, first_id: nil }, queries.summary([]))
    end
  end
end
