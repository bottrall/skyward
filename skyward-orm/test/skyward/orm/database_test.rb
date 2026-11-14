# frozen_string_literal: true

require 'test_helper'
require_relative '../../fixtures/tables/tables_fixtures'

describe Skyward::ORM::Database do
  signatures = File.expand_path('../../fixtures/tables/sig', __dir__)
  reader = Skyward::Core::Types::Reader.new(Skyward::Core::Signatures.load(signatures))
  refused = Skyward::ORM::Violation.new(kind: :check, constraint: nil, columns: [], message: 'refused')
  foreign = 'this transaction belongs to another fiber; start your own, or return the result to the block'

  counting_adapter = Class.new do
    attr_reader :comparisons, :decodings

    def initialize(adapter)
      @adapter = adapter
    end

    def compatible?(column, sql_type)
      @comparisons = comparisons.to_i + 1
      @adapter.compatible?(column, sql_type)
    end

    def decoding(column, value)
      @decodings = decodings.to_i + 1
      @adapter.decoding(column, value)
    end

    def sql_type(column) = @adapter.sql_type(column)

    def placeholder(position) = @adapter.placeholder(position)

    def encode(value) = @adapter.encode(value)
  end

  # Once closed, each comparison waits, inside the database's lock, until the gate opens.
  gated_adapter = Class.new do
    attr_reader :entered

    def initialize(adapter)
      @adapter = adapter
      @entered = Thread::Queue.new
    end

    def close = @gate = Thread::Queue.new

    def open = @gate.close

    def compatible?(column, sql_type)
      if @gate
        entered << true
        @gate.pop
      end
      @adapter.compatible?(column, sql_type)
    end

    def sql_type(column) = @adapter.sql_type(column)
  end

  faulty = Data.define(:connection, :statement, :reached) do
    def initialize(connection:, statement:, reached: true) = super

    def execute(sql, binds = [])
      return connection.execute(sql, binds) unless sql == statement

      connection.execute(sql, binds) if reached
      raise IOError, "raised at #{sql}"
    end

    # So the pool never rolls back what the database left open: that's the pool's own test's concern.
    def transaction_active? = false
  end

  let(:empty) { TestDatabase.empty }
  let(:connection) do
    empty.connect.tap do |connection|
      # lists.name allows NULL, which TablesFixtures::List#name doesn't.
      create_lists(connection)
      connection.execute("INSERT INTO lists (name) VALUES ('Home')")
      # Todo's own types, so todos matches it.
      columns = column_types.columns(todo).map do |column|
        "#{column.name} #{empty.adapter.sql_type(column)}#{' NOT NULL' unless column.nullable}"
      end
      connection.execute("CREATE TABLE todos (#{columns.join(', ')}, PRIMARY KEY (id))")
    end
  end
  let(:adapter) { empty.adapter }
  let(:check) { true }
  let(:column_types) { Skyward::ORM::Tables::ColumnTypes.new(reader) }
  let(:database) do
    Skyward::ORM::Database.new(
      adapter,
      Skyward::ORM::Connection::Pool.new(1, -> { connection }),
      column_types,
      empty.adapter.tables(connection),
      check:
    )
  end
  let(:two_connections) { pooled(-> { empty.connect }) }
  let(:prepared) { [] }
  let(:todo) { TablesFixtures::Todo }
  let(:list) { TablesFixtures::List }

  def create_lists(connection)
    connection.execute("CREATE TABLE lists (id #{empty.primary_key}, name TEXT CONSTRAINT lists_name_key UNIQUE)")
  end

  def mismatch(table)
    Skyward::ORM::Database::SchemaCheck.mismatch(
      table, column_types.columns(table), adapter.tables(connection), adapter
    )
  end

  def pooled(opener)
    Skyward::ORM::Database.new(adapter, Skyward::ORM::Connection::Pool.new(2, opener), column_types, [], check: false)
  end

  def recording(prepared_statements: true)
    Skyward::ORM::Database.new(
      adapter,
      Skyward::ORM::Connection::Pool.new(1, -> { TestDatabase::Preparing.new(connection:, prepared:) }),
      column_types,
      adapter.tables(connection),
      check: false,
      prepared_statements:
    )
  end

  def insert(database, name)
    database.connection do |connection|
      connection.execute("INSERT INTO lists (name) VALUES (#{adapter.placeholder(1)})", [name])
    end
  end

  def names(database = self.database)
    database.connection { |connection| connection.execute('SELECT name FROM lists ORDER BY id') }
  end

  def shared
    two_connections.tap { |database| database.connection { |connection| create_lists(connection) } }
  end

  describe '#connection' do
    it 'checks one out for the query alone outside a transaction' do
      assert_same(connection, database.connection { |checked_out| checked_out })
    end

    it 'refuses a child fiber the transaction it inherited' do
      error = assert_raises(FiberError) do
        database.transaction { Fiber.new { database.connection { nil } }.resume }
      end

      assert_equal foreign, error.message
    end

    it 'refuses a thread the transaction it inherited' do
      error = database.transaction do
        Thread.new do
          database.connection { nil }
        rescue FiberError => e
          e
        end.value
      end

      assert_equal foreign, error.message
    end

    it "yields the transaction's inside one, on the fiber that opened it" do
      database = two_connections
      outer, inner = database.transaction do
        database.connection { |first| database.connection { |second| [first, second] } }
      end

      assert_same outer, inner
    end
  end

  describe '#transaction' do
    it 'nests as a savepoint, which rolls back only its own writes' do
      database.transaction do
        insert(database, 'Work')
        database.transaction do
          insert(database, 'Garden')
          refused
        end
        :done
      end

      assert_equal [['Home'], ['Work']], names
    end

    it "rolls a nested one back when its block raises, keeping the outer one's writes" do
      database.transaction do
        insert(database, 'Work')
        begin
          database.transaction do
            insert(database, 'Garden')
            raise 'failed'
          end
        rescue RuntimeError
          nil
        end
        insert(database, 'Shed')
      end

      assert_equal [['Home'], ['Work'], ['Shed']], names
    end

    it 'commits a nested one with the outer one' do
      database.transaction do
        database.transaction { insert(database, 'Work') }
      end

      assert_equal [['Home'], ['Work']], names
    end

    it 'names each savepoint by its depth' do
      sent = []
      database = pooled(-> { TestDatabase::Recording.new(connection:, sent:) })
      database.transaction { database.transaction { database.transaction { :done } } }

      assert_equal ['BEGIN', 'SAVEPOINT skyward_1', 'SAVEPOINT skyward_2', 'RELEASE SAVEPOINT skyward_2',
                    'RELEASE SAVEPOINT skyward_1', 'COMMIT'],
                   sent.map(&:first)
    end

    it 'rolls back when interrupted just after its BEGIN reached the database' do
      interrupted = faulty.new(connection:, statement: 'BEGIN')
      error = assert_raises(IOError) { pooled(-> { interrupted }).transaction { :begun } }

      assert_equal ['raised at BEGIN', false], [error.message, connection.transaction_active?]
    end

    it 'rolls a nested one back when interrupted just after its savepoint reached the database' do
      sent = []
      interrupted = faulty.new(
        connection: TestDatabase::Recording.new(connection:, sent:),
        statement: 'SAVEPOINT skyward_1'
      )
      database = pooled(-> { interrupted })
      error = database.transaction { assert_raises(IOError) { database.transaction { :begun } } }

      assert_equal ['raised at SAVEPOINT skyward_1',
                    ['BEGIN', 'SAVEPOINT skyward_1', 'ROLLBACK TO SAVEPOINT skyward_1', 'RELEASE SAVEPOINT skyward_1',
                     'COMMIT']],
                   [error.message, sent.map(&:first)]
    end

    it "raises the start's own error when it never reached the database, which then refuses to roll back" do
      interrupted = faulty.new(connection:, statement: 'BEGIN', reached: false)
      error = assert_raises(IOError) { pooled(-> { interrupted }).transaction { :begun } }

      assert_equal 'raised at BEGIN', error.message
    end

    it "keeps the enclosing savepoint's writes, and raises the start's own error, when a savepoint never reached " \
       'the database' do
      database = pooled(-> { faulty.new(connection:, statement: 'SAVEPOINT skyward_3', reached: false) })
      error = database.transaction do
        database.transaction do
          insert(database, 'Work')
          # Rescued two levels up, so the level between rolls back what PostgreSQL's refused rollback aborted.
          assert_raises(IOError) { database.transaction { database.transaction { :begun } } }
        end
      end

      assert_equal ['raised at SAVEPOINT skyward_3', [['Home'], ['Work']]], [error.message, names(database)]
    end

    it "commits, and returns the block's value" do
      value = database.transaction do
        insert(database, 'Work')
        :done
      end

      assert_equal [:done, [['Home'], ['Work']]], [value, names]
    end

    it 'rolls back and raises again when the block raises' do
      assert_raises(RuntimeError) do
        database.transaction do
          insert(database, 'Work')
          raise 'failed'
        end
      end

      assert_equal [['Home']], names
    end

    it 'rolls back and returns a violation the block returns' do
      value = database.transaction do
        insert(database, 'Work')
        refused
      end

      assert_equal [refused, [['Home']]], [value, names]
    end

    it 'rolls back when the commit fails, so its connection goes back with no transaction open' do
      database.connection do |connection|
        connection.execute('CREATE TABLE shares (list_id INTEGER REFERENCES lists DEFERRABLE INITIALLY DEFERRED)')
      end
      error = assert_raises(StandardError) do
        database.transaction do
          database.connection do |connection|
            connection.execute('INSERT INTO shares VALUES (9)')
          end
        end
      end

      assert_equal %i[foreign_key begun], [database.violation(error, :shares)&.kind, database.transaction { :begun }]
    end

    it 'raises a rollback that fails once the transaction has begun' do
      lost = faulty.new(connection:, statement: 'ROLLBACK')
      error = assert_raises(IOError) { pooled(-> { lost }).transaction { raise 'failed' } }

      assert_equal 'raised at ROLLBACK', error.message
    end

    it 'leaves the fiber outside a transaction afterwards, even when the block raises' do
      assert_raises(RuntimeError) { database.transaction { raise 'failed' } }

      refute_predicate database, :transaction?
    end

    it "starts its own in a child fiber that inherited another's" do
      database = two_connections

      assert(database.transaction { Fiber.new { database.transaction { database.transaction? } }.resume })
    end

    it "leaves another thread's write in place when it rolls back" do
      database = shared
      begun = Thread::Queue.new
      written = Thread::Queue.new
      rolled_back = Thread.new do
        database.transaction do
          begun << true
          written.pop
          insert(database, 'Work')
          refused
        end
      end
      begun.pop
      insert(database, 'Home')
      written << true
      rolled_back.join

      assert_equal [['Home']], names(database)
    end

    it "leaves another fiber's write in place when it rolls back, after being suspended mid-block" do
      database = shared
      rolled_back = Fiber.new do
        database.transaction do
          Fiber.yield
          insert(database, 'Work')
          refused
        end
      end
      rolled_back.resume
      Fiber.new { insert(database, 'Home') }.resume
      rolled_back.resume

      assert_equal [['Home']], names(database)
    end

    it 'asks its connection to keep none of its own statements' do
      database = recording
      database.transaction { database.execute('SELECT 1') }

      assert_equal [['BEGIN', false], ['SELECT 1', true], ['COMMIT', false]], prepared
    end
  end

  describe '#transaction?' do
    it 'is false outside a transaction' do
      refute_predicate database, :transaction?
    end

    it 'is true inside one, on the fiber that opened it' do
      assert(database.transaction { database.transaction? })
    end

    it 'is false in a held transaction' do
      database.hold

      refute_predicate database, :transaction?
    ensure
      database.release
    end

    it 'is true inside a transaction in a held one, and false again after it' do
      database.hold

      assert_equal [true, false], [database.transaction { database.transaction? }, database.transaction?]
    ensure
      database.release
    end

    it 'is false in a child fiber that inherited it' do
      refute(database.transaction { Fiber.new { database.transaction? }.resume })
    end

    it 'is false in a thread that inherited it' do
      refute(database.transaction { Thread.new { database.transaction? }.value })
    end
  end

  describe '#hold' do
    it "runs its fiber's queries on the connection it holds" do
      database = two_connections
      database.hold
      outer, inner = database.connection { |first| database.connection { |second| [first, second] } }

      assert_same outer, inner
    ensure
      database.release
    end

    it 'refuses a child fiber the connection it holds' do
      database.hold
      error = assert_raises(FiberError) { Fiber.new { database.connection { nil } }.resume }

      assert_equal foreign, error.message
    ensure
      database.release
    end

    it 'refuses a thread the connection it holds' do
      database.hold
      error = Thread.new do
        database.connection { nil }
      rescue FiberError => e
        e
      end.value

      assert_equal foreign, error.message
    ensure
      database.release
    end

    it 'nests a transaction as a savepoint, which rolls back only its own writes' do
      database.hold
      insert(database, 'Work')
      database.transaction do
        insert(database, 'Garden')
        refused
      end

      assert_equal [['Home'], ['Work']], names
    ensure
      database.release
    end
  end

  describe '#release' do
    it 'does nothing when nothing is held' do
      assert_nil database.release
    end

    it 'rolls back what was written while held' do
      database.hold
      insert(database, 'Work')
      database.release

      assert_equal [['Home']], names
    end

    it 'returns the connection to the pool, and leaves the fiber holding nothing' do
      database.hold
      database.release

      assert_same(connection, Fiber.new { database.connection { |checked_out| checked_out } }.resume)
    end

    it 'returns the connection even when its rollback raises' do
      lost = faulty.new(connection:, statement: 'ROLLBACK')
      database = Skyward::ORM::Database.new(
        adapter, Skyward::ORM::Connection::Pool.new(1, -> { lost }), column_types, [], check: false
      )
      database.hold
      assert_raises(IOError) { database.release }

      assert_same(lost, Fiber.new { database.connection { |checked_out| checked_out } }.resume)
    end

    it 'asks its connection to keep neither the BEGIN #hold sent nor its ROLLBACK' do
      database = recording
      database.hold
      database.release

      assert_equal [['BEGIN', false], ['ROLLBACK', false]], prepared
    end
  end

  describe '#adapter' do
    it 'is the adapter it connected with' do
      assert_same adapter, database.adapter
    end
  end

  describe '#column_types' do
    it 'reads the column types of the signatures it was given' do
      assert_equal :enum, database.column_types.columns(todo).fetch(3).type
    end
  end

  describe '#tables' do
    it 'is the schema it was given' do
      assert_equal %i[lists todos], database.tables.map(&:name)
    end
  end

  describe '#execute' do
    it 'runs SQL on its connection and returns the rows' do
      assert_equal [['Home']], database.execute('SELECT name FROM lists')
    end

    it "binds its values to the SQL's placeholders" do
      assert_equal [['Home']], database.execute("SELECT name FROM lists WHERE id = #{adapter.placeholder(1)}", [1])
    end

    it 'asks its connection to keep the statement' do
      recording.execute('SELECT 1')

      assert_equal [['SELECT 1', true]], prepared
    end

    it 'asks it to keep nothing with prepared_statements: false' do
      recording(prepared_statements: false).execute('SELECT 1')

      assert_equal [['SELECT 1', false]], prepared
    end
  end

  describe '#check' do
    it 'passes table classes that match the schema' do
      assert_silent { database.check([todo]) }
    end

    it "validates each class's declarations before comparing it" do
      invalid = Class.new(Skyward::ORM::Record) do
        index :done
        attr_reader :id
      end
      error = assert_raises(Skyward::Core::BootError) { database.check([invalid]) }

      assert_equal "#{invalid} has no column done, which its index names. Add `attr_reader :done`, or fix the name.",
                   error.message
    end

    it "raises SchemaMismatch with a block for each class that doesn't match" do
      missing = Class.new(Skyward::ORM::Record) do
        table :notes
        attr_reader :id
      end
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.check([todo, list, missing]) }

      assert_equal "#{mismatch(list)}\n\n#{mismatch(missing)}", error.message
    end

    describe 'with an adapter that counts comparisons' do
      let(:adapter) { counting_adapter.new(empty.adapter) }

      it 'checks a class that matches once' do
        database.check([todo])
        comparisons = adapter.comparisons
        database.check([todo])

        assert_equal comparisons, adapter.comparisons
      end

      it "checks a class that doesn't match again" do
        assert_raises(Skyward::ORM::SchemaMismatch) { database.check([list]) }
        comparisons = adapter.comparisons
        assert_raises(Skyward::ORM::SchemaMismatch) { database.check([list]) }

        assert_equal comparisons * 2, adapter.comparisons
      end
    end
  end

  describe '#decoder' do
    let(:milk) do
      todo.new(
        id: 1,
        list_id: 1,
        title: 'Buy milk',
        priority: :normal,
        due_on: nil,
        done: false,
        created_at: Time.utc(2026, 10, 18, 9, 30)
      )
    end
    # Milk's values as the driver returns them.
    let(:values) do
      placeholders = Array.new(milk.to_h.size) { |index| adapter.placeholder(index + 1) }
      connection.execute(
        "INSERT INTO todos VALUES (#{placeholders.join(', ')})",
        milk.to_h.values.map { |value| adapter.encode(value) }
      )
      connection.execute('SELECT * FROM todos').fetch(0)
    end

    it 'checks its table class first' do
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.decoder(list, list, []) }

      assert_equal mismatch(list), error.message
    end

    it "reads each value by its table's column type, into a row" do
      assert_equal milk, database.decoder(todo, todo, []).call(values)
    end

    it "builds a table's decoder once" do
      assert_same database.decoder(todo, todo, []), database.decoder(todo, todo, [])
    end

    it 'builds one for each row class' do
      summary = Class.new(Skyward::ORM::Record) { attr_reader :done }

      refute_same database.decoder(todo, todo, []), database.decoder(todo, summary, [])
    end

    it 'builds one for each set of expressed members' do
      summary = Data.define(:done)

      refute_same database.decoder(todo, summary, []), database.decoder(todo, summary, [:done])
    end

    it "reads a member by the row class's own type before its table's column type" do
      assert_equal TablesFixtures::Labelled.new(priority: 'high'),
                   database.decoder(todo, TablesFixtures::Labelled, []).call(['high'])
    end

    it "reads an expressed member by the row class's own type" do
      assert_equal TablesFixtures::Progress.new(list_id: 1, finished: false),
                   database.decoder(todo, TablesFixtures::Progress, [:finished]).call(values.values_at(1, 5))
    end

    it "reads a member the row class doesn't type by its table's column of that name" do
      summary = Data.define(:title, :done)

      assert_equal summary.new(title: 'Buy milk', done: false),
                   database.decoder(todo, summary, []).call(values.values_at(2, 5))
    end

    it "passes through an expressed member the row class doesn't type, even one named like a column" do
      summary = Data.define(:done)

      assert_equal summary.new(done: 3), database.decoder(todo, summary, [:done]).call([3])
    end

    it 'passes through a member its table has no column for' do
      late = Class.new(Skyward::ORM::Record) { attr_reader :days_late }

      assert_equal late.new(days_late: 3), database.decoder(todo, late, []).call([3])
    end
  end

  describe '#cached_sql' do
    it "renders the SQL for a key it hasn't cached" do
      assert_equal 'SELECT 1', database.cached_sql([:select]) { 'SELECT 1' }
    end

    it 'freezes the SQL it renders' do
      assert_predicate database.cached_sql([:select]) { +'SELECT 1' }, :frozen?
    end

    it 'returns the SQL it cached for a key, without rendering it again' do
      cached = database.cached_sql([:select]) { 'SELECT 1' }

      assert_same cached, database.cached_sql([:select]) { 'SELECT 2' }
    end

    it 'caches nothing when rendering raises, so it renders again' do
      assert_raises(ArgumentError) { database.cached_sql([:select]) { raise ArgumentError } }

      assert_equal 'SELECT 2', database.cached_sql([:select]) { 'SELECT 2' }
    end

    it 'keeps the SQL added first when the key is rendered twice at once' do
      first = database.cached_sql([:select]) do
        database.cached_sql([:select]) { 'SELECT 1' }
        'SELECT 2'
      end

      assert_equal 'SELECT 1', first
    end

    describe 'once it holds as many shapes as it keeps' do
      before do
        Skyward::ORM::Database::SHAPES.times { |index| database.cached_sql([index]) { "SELECT #{index}" } }
        database.cached_sql([:added]) { 'SELECT 1' }
      end

      it 'drops the oldest to add another' do
        assert_equal 'SELECT again', database.cached_sql([0]) { 'SELECT again' }
      end

      it 'keeps the rest' do
        assert_equal 'SELECT 1', database.cached_sql([1]) { 'SELECT again' }
      end
    end
  end

  describe '#prepare' do
    it 'checks the table class' do
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.prepare(list) }

      assert_equal mismatch(list), error.message
    end

    describe "with another class's check holding the lock" do
      let(:adapter) { gated_adapter.new(empty.adapter) }

      it 'returns at once for a class it has checked' do
        database.check([todo])
        adapter.close
        checking = Thread.new do
          database.check([list])
        rescue Skyward::ORM::SchemaMismatch
          nil
        end
        adapter.entered.pop
        prepared = Thread.new { database.prepare(todo) }.join(5)
        adapter.open
        checking.join

        refute_nil prepared
      end
    end

    describe 'with the check off' do
      let(:check) { false }

      it "doesn't check it" do
        assert_silent { database.prepare(list) }
      end
    end
  end

  describe '#violation' do
    def violation(sql)
      connection.execute(sql)
    rescue StandardError => e
      database.violation(e, :lists)
    end

    it 'fills the violation from the schema it was given' do
      found = violation("INSERT INTO lists (name) VALUES ('Home')")

      assert_equal [:unique, 'lists_name_key', [:name]], [found&.kind, found&.constraint, found&.columns]
    end

    it "is nil for an error that isn't a violation" do
      assert_nil violation('SELECT * FROM missing')
    end
  end

  describe '#hashes' do
    it 'returns each row as its columns' do
      assert_equal [{ name: 'Home', title: 'Home' }], database.hashes('SELECT name, name AS title FROM lists', [])
    end

    it 'binds each value as a parameter, as the adapter stores it, and returns values as the driver does' do
      returned = {
        Skyward::ORM::Adapters::SQLite => { done: 1, due_on: '2026-10-01' },
        Skyward::ORM::Adapters::PostgreSQL => { done: 'true', due_on: '2026-10-01' }
      }

      assert_equal [returned.fetch(adapter)],
                   database.hashes('SELECT ? AS done, ? AS due_on', [true, Date.new(2026, 10, 1)])
    end

    it "refuses a count of ? that doesn't match the values, on every call" do
      errors = Array.new(2) { assert_raises(ArgumentError) { database.hashes('SELECT ?', []) }.message }

      assert_equal ['The SQL has 1 ?, each taking one value, but was given 0'] * 2, errors
    end

    describe 'with a connection that records what it sends' do
      let(:sent) { [] }
      let(:database) do
        Skyward::ORM::Database.new(
          adapter,
          Skyward::ORM::Connection::Pool.new(1, -> { TestDatabase::Recording.new(connection:, sent:) }),
          column_types,
          empty.adapter.tables(connection),
          check:
        )
      end

      it "rewrites the SQL's ? once for each count of values" do
        database.hashes('SELECT ? AS id', [1])
        database.hashes('SELECT ? AS id', [2])

        assert_same sent.dig(0, 0), sent.dig(1, 0)
      end
    end

    it 'refuses an Array, which the driver would spread across several ?, naming its position' do
      error = assert_raises(ArgumentError) { database.hashes('SELECT ?', [[1, 2]]) }

      assert_equal 'Skyward.query binds one value to each ?, but value 1 is an Array', error.message
    end

    it 'refuses an Array for SQL whose ? it has rewritten before' do
      database.hashes('SELECT ? AS id', [1])
      error = assert_raises(ArgumentError) { database.hashes('SELECT ? AS id', [[1, 2]]) }

      assert_equal 'Skyward.query binds one value to each ?, but value 1 is an Array', error.message
    end

    it 'refuses an empty Array, which the driver would bind to no ?' do
      assert_raises(ArgumentError) { database.hashes('SELECT ?', [[]]) }
    end

    it 'refuses a Hash, naming its position' do
      error = assert_raises(ArgumentError) { database.hashes('SELECT ?, ?', [1, {}]) }

      assert_equal 'Skyward.query binds one value to each ?, but value 2 is a Hash', error.message
    end

    it 'refuses values that would move the ones after them to other ?' do
      assert_raises(ArgumentError) do
        database.hashes('SELECT name FROM lists WHERE name = ? AND id = ? LIMIT ?', [['Home', 1], 2, {}])
      end
    end

    it "runs in the fiber's transaction, seeing a write it hasn't committed" do
      database = shared
      seen = database.transaction do
        insert(database, 'Work')
        database.hashes('SELECT name FROM lists', [])
      end

      assert_equal [{ name: 'Work' }], seen
    end

    it 'raises a violation the SQL causes' do
      error = assert_raises(Skyward::ORM::ViolationError) do
        database.hashes('INSERT INTO lists (name) VALUES (?)', ['Home'])
      end

      assert_equal [:unique, 'lists_name_key'], [error.violation.kind, error.violation.constraint]
    end

    it 'raises any other error as it is' do
      error = assert_raises(StandardError) { database.hashes('SELECT * FROM missing', []) }

      refute_kind_of Skyward::ORM::ViolationError, error
    end

    it 'asks its connection to keep the statement' do
      recording.hashes('SELECT ?', [1])

      assert_equal [[empty.shown('SELECT ?', [1]).fetch(0), true]], prepared
    end

    it 'asks it to keep nothing with prepared_statements: false' do
      recording(prepared_statements: false).hashes('SELECT ?', [1])

      assert_equal [[empty.shown('SELECT ?', [1]).fetch(0), false]], prepared
    end
  end

  describe '#rows' do
    let(:overdue) { TablesFixtures::Overdue }
    let(:due) { TablesFixtures::Due }

    it "builds the row class from the SQL's columns, by name" do
      assert_equal [overdue.new(title: 'Home', days_late: 3)],
                   database.rows(overdue, 'SELECT ? AS days_late, name AS title FROM lists', [3])
    end

    it 'reads each member by its type, and passes an untyped one through, frozen' do
      row = database.rows(due, "SELECT 'Milk' AS title, '2026-10-01' AS due_on, 'cold' AS note", []).fetch(0)

      assert_equal [due.new(title: 'Milk', due_on: Date.new(2026, 10, 1), note: 'cold'), true], [row, row.note.frozen?]
    end

    it 'reads NULL as nil' do
      assert_equal [due.new(title: 'Milk', due_on: nil, note: nil)],
                   database.rows(due, "SELECT 'Milk' AS title, NULL AS due_on, NULL AS note", [])
    end

    it 'refuses a column the row class has no member for, naming it' do
      error = assert_raises(ArgumentError) do
        database.rows(overdue, 'SELECT name AS title, 3 AS days_late, id, 1 AS done FROM lists', [])
      end

      assert_equal 'TablesFixtures::Overdue has no member for id, done, which the SQL returns', error.message
    end

    it 'refuses a member the SQL returns no column for, naming it, even with no rows' do
      error = assert_raises(ArgumentError) do
        database.rows(overdue, 'SELECT name AS title FROM lists WHERE id = 0', [])
      end

      assert_equal 'The SQL returns no days_late for TablesFixtures::Overdue', error.message
    end

    it 'asks its connection to keep one statement for rows that differ only in their values' do
      database = recording
      [3, 4].each { |days| database.rows(overdue, 'SELECT ? AS days_late, name AS title FROM lists', [days]) }

      assert_equal [[empty.shown('SELECT ? AS days_late, name AS title FROM lists', []).fetch(0), true]] * 2, prepared
    end

    describe 'with an adapter that counts decodings' do
      let(:adapter) { counting_adapter.new(empty.adapter) }

      it "compiles a row class's decoder once for the SQL's columns" do
        database.rows(overdue, 'SELECT 3 AS days_late, name AS title FROM lists', [])
        decodings = adapter.decodings
        database.rows(overdue, "SELECT 4 AS days_late, 'Work' AS title", [])

        assert_equal decodings, adapter.decodings
      end

      it 'compiles another for columns in another order' do
        database.rows(overdue, 'SELECT 3 AS days_late, name AS title FROM lists', [])
        decodings = adapter.decodings
        database.rows(overdue, 'SELECT name AS title, 3 AS days_late FROM lists', [])

        assert_equal decodings * 2, adapter.decodings
      end

      it "refuses columns that don't match the members every time" do
        mismatched = -> { database.rows(overdue, 'SELECT name AS title FROM lists', []) }
        begin
          mismatched.call
        rescue ArgumentError
          nil
        end

        assert_raises(ArgumentError) { mismatched.call }
      end
    end
  end

  describe '#migrate' do
    runner = Skyward::ORM::Migrations::Runner
    create_notes = runner.parse('20261001000000_create_notes.sql', "CREATE TABLE notes (id INTEGER);\n")
    note = Class.new(Skyward::ORM::Record) do
      table :notes
      attr_reader :id
    end

    it 'runs the migrations on a connection it checks out, through its adapter' do
      ran = database.migrate([create_notes])

      assert_equal [['20261001000000'], %i[lists notes schema_migrations todos]],
                   [ran, empty.adapter.tables(connection).map(&:name).sort]
    end

    it 'reads the schema again, so a class is checked against the tables the migrations made' do
      database.migrate([create_notes])

      assert_silent { database.check([note]) }
    end

    it 'checks a class again against the schema it migrated to, though it matched before' do
      database.check([todo])
      database.migrate([runner.parse('20261001000000_drop_title.sql', "ALTER TABLE todos DROP COLUMN title;\n")])
      error = assert_raises(Skyward::ORM::SchemaMismatch) { database.check([todo]) }

      assert_equal mismatch(todo), error.message
    end
  end

  describe '#rollback' do
    runner = Skyward::ORM::Migrations::Runner
    create_notes = runner.parse(
      '20261001000000_create_notes.sql',
      "CREATE TABLE notes (id INTEGER);\n-- down\nDROP TABLE notes;\n"
    )
    note = Class.new(Skyward::ORM::Record) do
      table :notes
      attr_reader :id
    end

    it 'rolls back on a connection it checks out, through its adapter' do
      database.migrate([create_notes])

      assert_equal [create_notes.version, %i[lists schema_migrations todos]],
                   [database.rollback([create_notes]), empty.adapter.tables(connection).map(&:name).sort]
    end

    it 'reads the schema again, so a class is checked against the tables it rolled back to' do
      database.migrate([create_notes])
      database.check([note])
      database.rollback([create_notes])

      assert_raises(Skyward::ORM::SchemaMismatch) { database.check([note]) }
    end
  end

  describe '#write' do
    it 'checks its table class before it writes' do
      assert_raises(Skyward::ORM::SchemaMismatch) { database.write(list, 'DELETE FROM missing', []) }
    end

    describe 'with the check off' do
      let(:check) { false }

      let(:inserting) { "INSERT INTO lists (name) VALUES (#{adapter.placeholder(1)})" }

      it 'returns how many rows the write changed' do
        insert(database, 'Work')

        assert_equal [2, 0],
                     [database.write(list, "UPDATE lists SET name = name || '!'", []),
                      database.write(list, "DELETE FROM lists WHERE name = 'Away'", [])]
      end

      it "returns a violation the write causes, filled in for the table written, with the database's message" do
        written = database.write(list, inserting, ['Home'])
        expected = Skyward::ORM::Violation.new(
          kind: :unique,
          constraint: 'lists_name_key',
          columns: [:name],
          message: empty.violation("INSERT INTO lists (name) VALUES ('Home')", :lists)&.message
        )

        assert_equal expected, written
      end

      it 'raises any other error as it is' do
        error = assert_raises(StandardError) { database.write(list, 'DELETE FROM missing', []) }

        refute_kind_of Skyward::ORM::ViolationError, error
      end
    end

    it 'asks its connection to keep the statement' do
      recording.write(list, 'DELETE FROM lists', [])

      assert_equal [['DELETE FROM lists', true]], prepared
    end

    it 'asks it to keep nothing with prepared_statements: false' do
      recording(prepared_statements: false).write(list, 'DELETE FROM lists', [])

      assert_equal [['DELETE FROM lists', false]], prepared
    end
  end

  describe '#write_returning' do
    it 'checks its table class before it writes' do
      assert_raises(Skyward::ORM::SchemaMismatch) do
        database.write_returning(list, list, 'DELETE FROM missing RETURNING id, name', [])
      end
    end

    describe 'with the check off' do
      let(:check) { false }

      let(:inserting) { "INSERT INTO lists (name) VALUES (#{adapter.placeholder(1)}) RETURNING id, name" }

      it "returns the rows the write returns, as the table's rows" do
        assert_equal [list.new(id: 2, name: 'Work')], database.write_returning(list, list, inserting, ['Work'])
      end

      it "returns a violation the write causes, filled in for the table written, with the database's message" do
        written = database.write_returning(list, list, inserting, ['Home'])
        expected = Skyward::ORM::Violation.new(
          kind: :unique,
          constraint: 'lists_name_key',
          columns: [:name],
          message: empty.violation("INSERT INTO lists (name) VALUES ('Home')", :lists)&.message
        )

        assert_equal expected, written
      end

      it 'raises any other error as it is' do
        error = assert_raises(StandardError) do
          database.write_returning(list, list, 'DELETE FROM missing RETURNING id, name', [])
        end

        refute_kind_of Skyward::ORM::ViolationError, error
      end
    end
  end
end
