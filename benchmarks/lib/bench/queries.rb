# frozen_string_literal: true

# rbs_inline: enabled

# The orm groups: Bench::Task's rows, read and queried on the database the
# process connected to.
module Bench::Queries
  extend self

  ROWS = 1_000 #: Integer

  MIGRATIONS = File.expand_path("#{__dir__}/../../db") #: String

  VERSIONS = {
    'sqlite' => 'SELECT sqlite_version() AS version',
    'postgresql' => "SELECT current_setting('server_version') AS version"
  }.freeze #: Hash[String, String]

  # SQLite's database is in memory, so it starts empty. PostgreSQL's keeps the
  # table from the last run, and the version of the migration that created it,
  # so both go first.
  # @rbs database: String
  # @rbs return: void
  def prepare(database)
    migrations = File.join(MIGRATIONS, database)
    forget(migrations) if database == 'postgresql'
    Skyward.migrate(migrations)
    Bench::Task.insert_all!(rows(ROWS))
  end

  # @rbs migrations: String
  # @rbs return: void
  def forget(migrations)
    Skyward.query('DROP TABLE IF EXISTS bench_tasks')
    return if Skyward.query("SELECT to_regclass('schema_migrations')::text AS name").fetch(0).fetch(:name).nil?

    Dir.glob('*.sql', base: migrations).each do |file|
      Skyward.query('DELETE FROM schema_migrations WHERE version = ?', file.split('_', 2).fetch(0))
    end
  end

  # @rbs count: Integer
  # @rbs return: Array[Hash[Symbol, untyped]]
  def rows(count)
    (1..count).map do |number|
      {
        title: "Task #{number}",
        done: number.even?,
        due_on: (number % 4).zero? ? nil : Date.new(2026, 1, 1) + number,
        created_at: Time.utc(2026, 1, 1) + (number * 60),
        score: number * 0.5
      }
    end
  end

  # @rbs database: String
  # @rbs return: String
  def version(database) = Skyward.query(VERSIONS.fetch(database)).fetch(0).fetch(:version)

  # @rbs group: String
  # @rbs return: Array[Bench::Scenario]
  def scenarios(group)
    [
      *[1, 100, ROWS].map { |count| rows_scenario(group, count) },
      Bench::Scenario.new(
        name: "#{group}.find_by",
        run: -> { Bench::Task.find_by(id: 500) },
        answer: ->(task) { summary([task].compact) },
        expected: { rows: 1, first_id: 500 },
        unit: nil,
        per_iteration: 1
      ),
      # Built and not run, so its answer is what it would bind.
      Bench::Scenario.new(
        name: "#{group}.build",
        run: -> { Bench::Task.where(done: false, id: 1..).order(:id).limit(20).to_sql },
        answer: ->(built) { { binds: built.fetch(1).size } },
        expected: { binds: 3 },
        unit: nil,
        per_iteration: 1
      )
    ]
  end

  # @rbs group: String
  # @rbs count: Integer
  # @rbs return: Bench::Scenario
  def rows_scenario(group, count)
    Bench::Scenario.new(
      name: "#{group}.rows.#{count}",
      run: -> { Bench::Task.all.limit(count).to_a },
      answer: ->(tasks) { summary(tasks) },
      expected: { rows: count, first_id: 1 },
      unit: 'rows',
      per_iteration: count
    )
  end

  # @rbs tasks: Array[Bench::Task]
  # @rbs return: Hash[Symbol, untyped]
  def summary(tasks) = { rows: tasks.size, first_id: tasks.first&.id }
end
