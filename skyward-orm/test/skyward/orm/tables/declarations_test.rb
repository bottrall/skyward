# frozen_string_literal: true

require 'test_helper'
require_relative '../../../fixtures/tables/tables_fixtures'

describe Skyward::ORM::Tables::Declarations do
  tables = Skyward::ORM::Tables
  fixtures = File.expand_path('../../../fixtures/tables/tables_fixtures.rb', __dir__)
  source = File.readlines(fixtures, chomp: true)
  line_of = ->(snippet) { source.index { |text| text.include?(snippet) }.to_i + 1 }

  let(:table) { Class.new { extend Skyward::ORM::Tables::Declarations } }

  def refusal(&)
    assert_raises(ArgumentError, &).message
  end

  it "builds the README's Todo schema" do
    expected = tables::Schema.new(
      table: :todos,
      primary_key: :id,
      columns: %i[id list_id title priority due_on done created_at],
      references: [tables::Reference.new(column: :list_id, table: TablesFixtures::List, on_delete: :cascade)],
      defaults: { priority: :normal, done: false, created_at: Skyward.sql('now()') },
      checks: [tables::Check.new(column: :title, rule: tables::Length.new(min: 1, max: 200))],
      uniques: [],
      indexes: [%i[list_id done]]
    )

    assert_equal expected, TablesFixtures::Todo.schema
  end

  describe '#schema' do
    it 'is empty, with the primary key id, until something is declared' do
      assert_same tables::Declarations::EMPTY, table.schema
    end
  end

  describe '#declared_at' do
    it 'is the file and line of each name a declaration names' do
      fixture = TablesFixtures::Misspelt
      declared = [
        TablesFixtures::Todo.declared_at(:table, :todos),
        fixture.declared_at(:primary_key, :cdoe),
        fixture.declared_at(:references, :lsit_id),
        fixture.declared_at(:default, :dnoe),
        fixture.declared_at(:unique, :emial),
        fixture.declared_at(:check, :titel),
        fixture.declared_at(:index, :due_on),
        fixture.declared_at(:attr_reader, :email)
      ]
      snippets = ['table :todos', 'primary_key :cdoe', 'references :lsit_id', 'default dnoe:', 'unique :emial',
                  'check :titel', 'index :lsit_id', 'attr_reader :code']

      assert_equal snippets.map { |snippet| [fixtures, line_of.call(snippet)] }, declared
    end

    it 'is nil for a name no declaration names' do
      assert_nil TablesFixtures::Literal.declared_at(:primary_key, :id)
    end

    it 'keeps none for an anonymous class' do
      table.index :done

      assert_nil table.declared_at(:index, :done)
    end

    it "keeps none for eval'd code, which has no file" do
      table.define_singleton_method(:name) { 'Named' }
      table.instance_eval('index :done') # rubocop:disable Style/EvalWithLocation -- eval'd code with no file is what's tested

      assert_nil table.declared_at(:index, :done)
    end
  end

  describe '#table_name' do
    it 'is the declared table' do
      table.table :todos

      assert_equal :todos, table.table_name
    end

    it "says to declare a table when there isn't one" do
      error = assert_raises(Skyward::Core::BootError) { table.table_name }

      assert_equal "#{table} has no table. Add `table :name` to its body.", error.message
    end

    it "points at the class's name" do
      error = assert_raises(Skyward::Core::BootError) { TablesFixtures::Typed.table_name }
      expected = <<~MESSAGE.chomp
        TablesFixtures::Typed has no table. Add `table :name` to its body.

            #{fixtures.delete_prefix("#{Dir.pwd}/")}:#{line_of.call('class Typed <')}
            class Typed < Skyward::ORM::Record
                  ^^^^^
      MESSAGE

      assert_equal expected, error.message
    end
  end

  describe '#attr_reader' do
    it 'defines the readers and returns their names' do
      assert_equal %i[id title], table.attr_reader(:id, 'title')
    end

    it 'adds each reader as a column, in order' do
      table.attr_reader :id
      table.attr_reader :title, :done

      assert_equal %i[id title done], table.schema.columns
    end

    it 'refuses a column it already has' do
      table.attr_reader :id
      message = refusal { table.attr_reader :title, :id }

      assert_equal "#{table} already has a column id", message
    end

    it 'refuses a column given twice' do
      assert_equal("#{table} already has a column id", refusal { table.attr_reader :id, :id })
    end

    it 'builds rows of the columns so far' do
      table.attr_reader :id
      table.attr_reader :title
      row = table.allocate
      row.send(:initialize_columns, { id: 1, title: 'Buy milk' })

      assert_equal({ id: 1, title: 'Buy milk' }, row.to_h)
    end

    it "redefines the rows' methods without a warning" do
      table.attr_reader :id
      verbose = $VERBOSE
      $VERBOSE = true

      assert_silent { table.attr_reader :title }
    ensure
      $VERBOSE = verbose
    end
  end

  describe '#table' do
    it 'names the table' do
      table.table :todos

      assert_equal :todos, table.schema.table
    end

    it "refuses a name that isn't a Symbol" do
      assert_equal(
        "#{table} table \"todos\": the table's name must be a Symbol, such as :todos",
        refusal { table.table 'todos' }
      )
    end
  end

  describe '#primary_key' do
    it 'names the primary key' do
      table.primary_key :uuid

      assert_equal :uuid, table.schema.primary_key
    end

    it "refuses a column that isn't a Symbol" do
      assert_equal(
        "#{table} primary_key \"uuid\": a column's name must be a Symbol, such as :title",
        refusal { table.primary_key 'uuid' }
      )
    end
  end

  describe '#references' do
    it 'adds a foreign key, with no on_delete: unless one is given' do
      table.references :list_id, TablesFixtures::List
      table.references :owner_id, TablesFixtures::List, on_delete: :set_null

      assert_equal [
        tables::Reference.new(column: :list_id, table: TablesFixtures::List, on_delete: nil),
        tables::Reference.new(column: :owner_id, table: TablesFixtures::List, on_delete: :set_null)
      ],
                   table.schema.references
    end

    it "refuses a column that isn't a Symbol" do
      assert_equal(
        "#{table} references \"list_id\": a column's name must be a Symbol, such as :title",
        refusal { table.references 'list_id', TablesFixtures::List }
      )
    end

    it "refuses a class that isn't a table class" do
      assert_equal(
        "#{table} references :list_id: it references String, which isn't a table class",
        refusal { table.references :list_id, String }
      )
    end

    it "refuses something that isn't a class" do
      assert_equal(
        "#{table} references :list_id: it references :lists, which isn't a table class",
        refusal { table.references :list_id, :lists }
      )
    end

    it "refuses an on_delete: SQL doesn't have" do
      assert_equal(
        "#{table} references :list_id: on_delete: is :destroy, but it can only be " \
        ':cascade, :restrict, :set_null, :set_default, :no_action or nil',
        refusal { table.references :list_id, TablesFixtures::List, on_delete: :destroy }
      )
    end
  end

  describe '#default' do
    it 'adds to the defaults declared before' do
      table.default done: false
      table.default created_at: Skyward.sql('now()'), done: true

      assert_equal({ done: true, created_at: Skyward.sql('now()') }, table.schema.defaults)
    end
  end

  describe '#unique' do
    it 'adds a unique constraint on its columns' do
      table.unique :email
      table.unique :list_id, :title

      assert_equal [[:email], %i[list_id title]], table.schema.uniques
    end

    it 'refuses no columns' do
      assert_equal("#{table} unique: it needs at least one column", refusal { table.unique })
    end

    it "refuses a column that isn't a Symbol" do
      assert_equal(
        "#{table} unique :list_id, \"title\": a column's name must be a Symbol, such as :title",
        refusal { table.unique :list_id, 'title' }
      )
    end
  end

  describe '#check' do
    def rule(...)
      table.check(...)
      table.schema.checks.fetch(0).rule
    end

    it 'adds a check of an SQL expression' do
      assert_equal Skyward.sql('length(title) > 0'), rule(:title, Skyward.sql('length(title) > 0'))
    end

    it 'adds a check of a length range' do
      assert_equal tables::Length.new(min: 1, max: 200), rule(:title, length: 1..200)
    end

    it 'reads a range that excludes its end as one shorter' do
      assert_equal tables::Length.new(min: 1, max: 199), rule(:title, length: 1...200)
    end

    it 'leaves a length with no end unbounded above' do
      assert_equal tables::Length.new(min: 1, max: nil), rule(:title, length: 1..)
    end

    it 'leaves an exclusive length with no end unbounded above' do
      assert_equal tables::Length.new(min: 1, max: nil), rule(:title, length: 1...)
    end

    it 'leaves a length with no beginning unbounded below' do
      assert_equal tables::Length.new(min: nil, max: 199), rule(:title, length: ...200)
    end

    it 'keeps each check, for its column' do
      table.check :title, length: 1..200
      table.check :body, Skyward.sql("body <> ''")

      assert_equal %i[title body], table.schema.checks.map(&:column)
    end

    it "refuses a column that isn't a Symbol" do
      assert_equal(
        "#{table} check \"title\": a column's name must be a Symbol, such as :title",
        refusal { table.check 'title', length: 1..200 }
      )
    end

    it 'refuses both SQL and a length' do
      assert_equal(
        "#{table} check :title: it takes Skyward.sql(\"...\") or length:, not both",
        refusal { table.check :title, Skyward.sql('length(title) > 0'), length: 1..200 }
      )
    end

    it 'refuses a plain String' do
      assert_equal(
        "#{table} check :title: write the SQL as Skyward.sql(\"length(title) > 0\"), not a plain String",
        refusal { table.check :title, 'length(title) > 0' }
      )
    end

    it 'refuses anything else in place of SQL' do
      assert_equal(
        "#{table} check :title: it takes Skyward.sql(\"...\") or length:, not 200",
        refusal { table.check :title, 200 }
      )
    end

    it 'refuses neither SQL nor a length' do
      assert_equal("#{table} check :title: it needs Skyward.sql(\"...\") or length:", refusal { table.check :title })
    end

    it "refuses a length that isn't a Range" do
      assert_equal(
        "#{table} check :title: length: must be a Range of Integers, such as 1..200, not 200",
        refusal { table.check :title, length: 200 }
      )
    end

    it 'refuses a range of something other than Integers' do
      assert_equal(
        "#{table} check :title: length: must be a Range of Integers, such as 1..200, not \"a\"..\"z\"",
        refusal { table.check :title, length: 'a'..'z' }
      )
    end

    it 'refuses a range with no bounds' do
      assert_equal(
        "#{table} check :title: length: nil..nil needs a bound, such as 1..200",
        refusal { table.check :title, length: nil..nil }
      )
    end

    it 'refuses an empty range' do
      assert_equal("#{table} check :title: length: 1...1 is empty", refusal { table.check :title, length: 1...1 })
    end
  end

  describe '#index' do
    it 'adds an index on its columns' do
      table.index :list_id, :done

      assert_equal [%i[list_id done]], table.schema.indexes
    end

    it 'refuses no columns' do
      assert_equal("#{table} index: it needs at least one column", refusal { table.index })
    end
  end
end
