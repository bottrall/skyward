# frozen_string_literal: true

# Skyward::ORM::Query and Skyward::ORM::Projection differ only in what a write
# returns, so everything else is here.
# @rbs generic R
module Skyward::ORM::Queries::Clauses
  include Enumerable #[R]

  # @rbs!
  #   type direction = :asc | :desc
  #   type condition = Comparison | Fragment | Negation | Disjunction
  #   type scope = :all | :start | :narrowed
  #   type parts = [singleton(Skyward::ORM::Record), Array[Join], scope, Array[condition],
  #                 Array[[Symbol, direction]], Array[Symbol], Integer?, Integer?]

  DIRECTIONS = %i[asc desc].freeze #: Array[direction]

  COUNT = Skyward::ORM::Tables::Column.new(
    name: :count, type: :integer, nullable: false, symbols: [], element: nil
  ) #: Skyward::ORM::Tables::Column

  Comparison = Data.define(
    :column, #: Symbol
    :operator, #: String
    :value #: untyped
  )

  Fragment = Data.define(
    :sql, #: String
    :values #: Array[untyped]
  )

  Negation = Data.define(
    :conditions #: Array[condition]
  )

  Disjunction = Data.define(
    :left, #: Array[condition]
    :right #: Array[condition]
  )

  Join = Data.define(
    :keyword, #: String
    :table, #: singleton(Skyward::ORM::Record)
    :on #: Hash[Symbol, Symbol]
  )

  InList = Data.define(
    :placeholders, #: Integer
    :null #: bool
  )

  # @rbs @table: singleton(Skyward::ORM::Record)
  # @rbs @session: Skyward::ORM::Connection::Session
  # @rbs @joins: Array[Join]
  # @rbs @row: Class
  # @rbs @expressions: Hash[Symbol, String]
  # @rbs @scope: scope
  # @rbs @conditions: Array[condition]
  # @rbs @orders: Array[[Symbol, direction]]
  # @rbs @groups: Array[Symbol]
  # @rbs @limit: Integer?
  # @rbs @offset: Integer?

  # scope: is :all only for an explicit Todo.all, which may update or delete
  # every row, and :narrowed once a where or exclude has been called, even
  # with nothing, which an insert refuses.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs joins: Array[Join]
  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs scope: scope
  # @rbs conditions: Array[condition]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs limit: Integer?
  # @rbs offset: Integer?
  # @rbs return: void
  def initialize(
    table,
    session,
    joins: [],
    row: table,
    expressions: {},
    scope: :start,
    conditions: [],
    orders: [],
    groups: [],
    limit: nil,
    offset: nil
  )
    @table = table
    @session = session
    @joins = [*joins].freeze
    @row = row
    @expressions = expressions.dup.freeze
    @scope = scope
    @conditions = [*conditions].freeze
    @orders = [*orders].freeze
    @groups = [*groups].freeze
    @limit = limit
    @offset = offset
    freeze
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: self
  def join(table, **on) = with(joins: [*@joins, joined('JOIN', table, on)])

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: self
  def left_join(table, **on) = with(joins: [*@joins, joined('LEFT JOIN', table, on)])

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: self
  def where(sql = nil, *values, **conditions)
    with(scope: :narrowed, conditions: [*@conditions, *build(sql, values, conditions)])
  end

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: self
  def exclude(sql = nil, *values, **conditions)
    built = build(sql, values, conditions)
    with(scope: :narrowed, conditions: built.empty? ? @conditions : [*@conditions, Negation.new(conditions: built)])
  end

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: self
  def or(sql = nil, *values, **conditions)
    raise ArgumentError, "#{@table} has no conditions to or with. Start with where or exclude." if @conditions.empty?

    built = build(sql, values, conditions)
    raise ArgumentError, "#{@table} has nothing to or with. Give or conditions or SQL." if built.empty?

    with(conditions: [Disjunction.new(left: @conditions, right: built)])
  end

  # @rbs *columns: Symbol
  # @rbs **directions: direction
  # @rbs return: self
  def order(*columns, **directions)
    Skyward::ORM::Statements.require_columns(@table, [*columns, *directions.keys])
    # The direction is written into the SQL, so only these two may reach it.
    column, direction = directions.find { |_, candidate| !DIRECTIONS.include?(candidate) }
    raise ArgumentError, "#{@table} can't order #{column} by #{direction.inspect}, only :asc or :desc" if column

    with(orders: [*@orders, *columns.map { |name| [name, :asc] }, *directions.to_a])
  end

  # @rbs *columns: Symbol
  # @rbs return: self
  def group(*columns)
    Skyward::ORM::Statements.require_columns(@table, columns)
    with(groups: [*@groups, *columns])
  end

  # @rbs count: Integer
  # @rbs return: self
  def limit(count) = with(limit: require_count(:limit, count))

  # @rbs count: Integer
  # @rbs return: self
  def offset(count) = with(offset: require_count(:offset, count))

  # @rbs other: Skyward::ORM::Query[untyped]
  # @rbs return: self
  def merge(other)
    require_query(other)
    table, joins, scope, conditions, orders, groups, limit, offset = other.parts
    raise ArgumentError, "#{@table} can't merge a query of #{table}, a different table class" unless table == @table

    with(
      joins: merged_joins(joins),
      scope: merged_scope(scope),
      conditions: [*@conditions, *conditions],
      orders: [*@orders, *orders],
      groups: [*@groups, *groups],
      limit: limit || @limit,
      offset: offset || @offset
    )
  end

  # Steep ties the row class to S only through its new, so the query keeps it
  # as the Class it is.
  # @rbs [S] (Skyward::ORM::_Row[S] row, **String expressions) -> Skyward::ORM::Projection[S]
  def into(row, **expressions)
    klass = row #: Class
    require_members(klass, expressions)
    with(query: Skyward::ORM::Projection, row: klass, expressions:)
  end

  # Ordered by the primary key when nothing else orders it, so both databases
  # return the same row.
  # @rbs () -> R?
  #    | (Integer count) -> Array[R]
  def first(count = nil)
    return super if count

    rows(@orders.empty? ? [[@table.schema.primary_key, :asc]] : @orders, 1).first
  end

  # @rbs **conditions: untyped
  # @rbs return: R?
  def find_by(**conditions) = where(**conditions).first

  # PostgreSQL refuses an ORDER BY beside COUNT(*), so the count leaves it out.
  # A LIMIT beside it would limit the one row COUNT(*) returns, so a page is
  # counted through a subquery, as the groups of a grouped query are.
  # @rbs (*untyped args) ?{ (R) -> boolish } -> Integer
  def count(*args, &block)
    return super if block || !args.empty?

    database = @session.database
    prepare(database)
    sql, binds = selecting(database, :count, [], @limit) do |from|
      counted = @groups.empty? && @limit.nil? && @offset.nil? ? from : %(FROM (SELECT 1 #{from}) AS "counted")
      "SELECT COUNT(*) #{counted}"
    end
    # PostgreSQL's driver returns every value as text, so the adapter reads it.
    database.adapter.decode(COUNT, database.execute(sql, binds).fetch(0).fetch(0))
  end

  # Order can't change whether the query has a row, so it's left out, and a
  # limit of 0 has none.
  # @rbs return: bool
  def exists?
    database = @session.database
    prepare(database)
    sql, binds = selecting(database, :exists, [], [@limit, 1].compact.min) { |from| "SELECT 1 #{from}" }
    !database.execute(sql, binds).empty?
  end

  # @rbs () { (R) -> void } -> self
  #    | () -> Enumerator[R, self]
  def each(&block)
    return enum_for(:each) unless block

    rows(@orders, @limit).each(&block)
    self
  end

  # @rbs return: [String, Array[untyped]]
  def to_sql = statement(@session.database, @orders, @limit)

  protected

  # rbs-inline writes a protected method as public, so Steep would let an app
  # call this, though Ruby won't.
  # @rbs return: parts
  def parts = [@table, @joins, @scope, @conditions, @orders, @groups, @limit, @offset]

  private

  # Steep can't tie the class it builds to self, or the row class to S, so
  # each public method types the query it returns.
  # @rbs query: Class
  # @rbs joins: Array[Join]
  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs scope: scope
  # @rbs conditions: Array[condition]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs limit: Integer?
  # @rbs offset: Integer?
  # @rbs return: untyped
  def with(
    # Steep reads self.class in a module as the module, though it's always the
    # class that includes it.
    query: self.class, # steep:ignore IncompatibleAssignment
    joins: @joins,
    row: @row,
    expressions: @expressions,
    scope: @scope,
    conditions: @conditions,
    orders: @orders,
    groups: @groups,
    limit: @limit,
    offset: @offset
  )
    query.new(@table, @session, joins:, row:, expressions:, scope:, conditions:, orders:, groups:, limit:, offset:)
  end

  # @rbs keyword: String
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs on: Hash[Symbol, Symbol]
  # @rbs return: Join
  def joined(keyword, table, on)
    unless table.is_a?(Class) && table < Skyward::ORM::Record && table.schema.table
      raise ArgumentError, "#{@table} can't join #{table.inspect}, which isn't a table class"
    end
    if present?(table)
      raise ArgumentError, "#{@table} can't join #{table}, since #{table.table_name} is already in the query"
    end
    raise ArgumentError, "#{@table} can't join #{table} on nothing. Give it columns, such as list_id: :id" if on.empty?

    Skyward::ORM::Statements.require_columns(@table, on.keys)
    Skyward::ORM::Statements.require_columns(table, on.values)
    Join.new(keyword:, table:, on:)
  end

  # @rbs other: untyped
  # @rbs return: void
  def require_query(other)
    if other.is_a?(Skyward::ORM::Projection)
      raise ArgumentError,
            "#{@table} can't merge a projection, whose row class and expressions would have nowhere to go. " \
            'Merge the query before its into.'
    end
    return if other.is_a?(Skyward::ORM::Query)

    raise ArgumentError, "#{@table} can't merge #{other.inspect}, which isn't a query"
  end

  # Two scopes that each join a table the same way compose, so an identical
  # join is kept once.
  # @rbs joins: Array[Join]
  # @rbs return: Array[Join]
  def merged_joins(joins)
    added = joins - @joins
    conflict = added.find { |join| present?(join.table) }
    if conflict
      raise ArgumentError,
            "#{@table} can't merge a different join of #{conflict.table}, " \
            "since #{conflict.table.table_name} is already in the query"
    end

    [*@joins, *added]
  end

  # Merging only ever narrows, so every row may be changed only when both
  # queries said so with an explicit all.
  # @rbs scope: scope
  # @rbs return: scope
  def merged_scope(scope)
    return :narrowed if [@scope, scope].include?(:narrowed)

    @scope == :all && scope == :all ? :all : :start
  end

  # @rbs sql: String?
  # @rbs values: Array[untyped]
  # @rbs conditions: Hash[Symbol, untyped]
  # @rbs return: Array[condition]
  def build(sql, values, conditions)
    Skyward::ORM::Statements.require_conditions(@session.database.column_types, @table, conditions)
    [(Fragment.new(sql:, values:) if sql), *conditions.flat_map { |column, value| comparisons(column, value) }].compact
  end

  # @rbs column: Symbol
  # @rbs value: untyped
  # @rbs return: Array[Comparison]
  def comparisons(column, value)
    return [Comparison.new(column:, operator: '=', value:)] unless value.is_a?(Range)

    ends = [
      (Comparison.new(column:, operator: '>=', value: value.begin) unless value.begin.nil?),
      (Comparison.new(column:, operator: value.exclude_end? ? '<' : '<=', value: value.end) unless value.end.nil?)
    ].compact
    raise ArgumentError, "#{@table} can't match #{column} to #{value.inspect}, a range with neither end" if ends.empty?

    ends
  end

  # @rbs return: Array[String]
  def clauses
    [
      ('into expressions' unless @expressions.empty?),
      ('join' unless @joins.empty?),
      ('order' unless @orders.empty?),
      ('group' unless @groups.empty?),
      ('limit' if @limit),
      ('offset' if @offset)
    ].compact
  end

  # @rbs clauses: Array[String]
  # @rbs return: String
  def listing(clauses)
    *others, last = clauses
    others.empty? ? last.to_s : "#{others.join(', ')} or #{last}"
  end

  # Neither PostgreSQL nor SQLite (as it's usually built) takes a JOIN,
  # ORDER BY, GROUP BY, LIMIT or OFFSET on an UPDATE or DELETE, and an into
  # expression, such as an aggregate, means nothing portable in its RETURNING.
  # @rbs method: Symbol
  # @rbs return: void
  def require_writable(method)
    refused = clauses
    unless refused.empty?
      raise ArgumentError,
            "#{@table} can't #{method} a query with #{listing(refused)}, which PostgreSQL and SQLite don't both support"
    end
    return unless @conditions.empty? && @scope != :all

    raise ArgumentError,
          "#{@table} can't #{method} a query with no conditions, which would change every row. " \
          "Narrow it with where or exclude, or start from #{@table}.all to change every row."
  end

  # @rbs method: Symbol
  # @rbs count: Integer
  # @rbs return: Integer
  def require_count(method, count)
    return count if count.is_a?(Integer) && !count.negative?

    raise ArgumentError, "#{@table} can't #{method} by #{count.inspect}, only by a non-negative Integer"
  end

  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs return: void
  def require_members(row, expressions)
    members = Skyward::ORM::Tables::Members.of(row)
    unknown = expressions.keys - members
    raise ArgumentError, "#{row} has no member #{unknown.join(', ')} to take an expression" unless unknown.empty?

    unread = members - @table.schema.columns - expressions.keys
    return if unread.empty?

    raise ArgumentError, "#{@table} has no column #{unread.join(', ')}, so #{row} needs an expression for it"
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: [String, Array[untyped]]
  def statement(database, orders, limit)
    selecting(database, [:select, @row, @expressions], orders, limit) do |from|
      columns = Skyward::ORM::Tables::Members.of(@row).map do |member|
        expression = @expressions.fetch(member, nil)
        expression ? "#{expression} AS #{Skyward::ORM::Statements.quote(member)}" : qualified(member)
      end.join(', ')
      "SELECT #{columns} #{from}"
    end
  end

  # The SQL is rendered from the conditions' shapes, not the conditions, so
  # two queries that share a key can't render different SQL.
  # @rbs database: Skyward::ORM::Database
  # @rbs kind: Symbol | Array[untyped]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs &: (String from) -> String
  # @rbs return: [String, Array[untyped]]
  def selecting(database, kind, orders, limit)
    shapes, binds = bound(database)
    # A Hash's == ignores the order of its pairs, but ON joins them in it.
    joins = @joins.map { |join| [join.keyword, join.table, join.on.to_a] }
    key = [kind, @table, joins, orders, @groups, limit.nil?, @offset.nil?, shapes]
    sql = database.cached_sql(key) { yield from(database, shapes, orders, limit) }
    [sql, [*binds, *[limit, @offset].compact]]
  end

  # The binds follow the order in which from numbers their placeholders.
  # @rbs database: Skyward::ORM::Database
  # @rbs return: [Array[condition], Array[untyped]]
  def bound(database)
    shaped(database.adapter, Skyward::ORM::Statements.by_name(database.column_types, @table), @conditions)
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs columns: Hash[Symbol, Skyward::ORM::Tables::Column]
  # @rbs conditions: Array[condition]
  # @rbs return: [Array[condition], Array[untyped]]
  def shaped(adapter, columns, conditions)
    pairs = conditions.map { |condition| shape(adapter, columns, condition) }
    [pairs.map { |shape, _| shape }, pairs.flat_map { |_, binds| binds }]
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs columns: Hash[Symbol, Skyward::ORM::Tables::Column]
  # @rbs condition: condition
  # @rbs return: [condition, Array[untyped]]
  def shape(adapter, columns, condition)
    case condition
    when Comparison then compared(adapter, columns.fetch(condition.column), condition)
    when Fragment
      binds = condition.values.map { |value| adapter.encode(value) }
      Skyward::ORM::Statements::Placeholders.require_scalars(binds, 'An SQL condition')
      [condition.with(values: binds.map { :bound }), binds]
    when Negation
      shapes, binds = shaped(adapter, columns, condition.conditions)
      [Negation.new(conditions: shapes), binds]
    when Disjunction
      left, left_binds = shaped(adapter, columns, condition.left)
      right, right_binds = shaped(adapter, columns, condition.right)
      [Disjunction.new(left:, right:), [*left_binds, *right_binds]]
    end
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs column: Skyward::ORM::Tables::Column
  # @rbs comparison: Comparison
  # @rbs return: [Comparison, Array[untyped]]
  def compared(adapter, column, comparison)
    value = comparison.value
    case value
    when nil then [comparison, []]
    when Array
      present = value.compact
      [
        comparison.with(value: InList.new(placeholders: present.size, null: value.include?(nil))),
        present.map { |item| Skyward::ORM::Statements.encode(adapter, column, item) }
      ]
    else [comparison.with(value: :bound), [Skyward::ORM::Statements.encode(adapter, column, value)]]
    end
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs shapes: Array[condition]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: String
  def from(database, shapes, orders, limit)
    adapter = database.adapter
    where, count = filter(database, shapes, 1)
    columns = Skyward::ORM::Statements.by_name(database.column_types, @table)
    ordered = orders.map do |column, direction|
      "#{adapter.comparable(columns[column]&.type || :untyped, qualified(column))} #{direction.upcase}"
    end
    # The limit and offset are bound rather than written in, so every page of a
    # query shares one SQL string.
    paging = [limit, @offset].compact
    [
      "FROM #{Skyward::ORM::Statements.quote(@table.table_name)}",
      *@joins.map { |join| joining(join) },
      where,
      ("GROUP BY #{@groups.map { |column| qualified(column) }.join(', ')}" unless @groups.empty?),
      ("ORDER BY #{ordered.join(', ')}" unless orders.empty?),
      limit ? "LIMIT #{adapter.placeholder(count + 1)}" : (adapter.unlimited if @offset),
      ("OFFSET #{adapter.placeholder(count + paging.size)}" if @offset)
    ].compact.join(' ')
  end

  # @rbs join: Join
  # @rbs return: String
  def joining(join)
    on = join.on.map { |column, joined| "#{qualified(column)} = #{qualified(joined, join.table)}" }.join(' AND ')
    "#{join.keyword} #{Skyward::ORM::Statements.quote(join.table.table_name)} ON #{on}"
  end

  # An UPDATE binds its SET values first, so its WHERE's numbered placeholders
  # start after them.
  # @rbs database: Skyward::ORM::Database
  # @rbs shapes: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String?, Integer]
  def filter(database, shapes, position)
    clauses, count = conjunction(database, shapes, position)
    [("WHERE #{clauses}" unless shapes.empty?), count]
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs shapes: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def conjunction(database, shapes, position)
    none = [[], 0] #: [Array[String], Integer]
    clauses, count = shapes.reduce(none) do |(sqls, taken), shape|
      sql, placeholders = render(database, shape, position + taken)
      [[*sqls, shape.is_a?(Disjunction) && shapes.size > 1 ? "(#{sql})" : sql], taken + placeholders]
    end
    [clauses.join(' AND '), count]
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs shape: condition
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def render(database, shape, position)
    case shape
    when Comparison then comparison(database, shape, position)
    when Fragment then fragment(database.adapter, shape, position)
    when Negation then negation(database, shape.conditions, position)
    when Disjunction
      left, left_count = alternative(database, shape.left, position)
      right, right_count = alternative(database, shape.right, position + left_count)
      ["#{left} OR #{right}", left_count + right_count]
    end
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs comparison: Comparison
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def comparison(database, comparison, position)
    adapter = database.adapter
    name = qualified(comparison.column)
    value = comparison.value
    case value
    when nil then ["#{name} IS NULL", 0]
    when InList then within(adapter, name, value, position)
    else
      column = Skyward::ORM::Statements.by_name(database.column_types, @table).fetch(comparison.column)
      # = compares exactly as the column stores its values, and only a range's
      # ends need them in order.
      compared = comparison.operator == '=' ? name : adapter.comparable(column.type, name)
      ["#{compared} #{comparison.operator} #{adapter.placeholder(position)}", 1]
    end
  end

  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs fragment: Fragment
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def fragment(adapter, fragment, position)
    count = fragment.values.size
    sql = Skyward::ORM::Statements::Placeholders.replace(fragment.sql, count) do |index|
      adapter.placeholder(position + index - 1)
    end
    # A -- comment runs to the end of its line, so the closing parenthesis
    # goes on a line of its own.
    ["(#{sql}#{"\n" if sql.include?('--')})", count]
  end

  # NOT of an unknown is unknown, so a row whose column is NULL would be left
  # out, though it doesn't match. An untyped column may hold NULL, and an SQL
  # string's columns can't be known.
  # @rbs database: Skyward::ORM::Database
  # @rbs shapes: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def negation(database, shapes, position)
    sql, count = conjunction(database, shapes, position)
    nullable = database.column_types.columns(@table).select { |column| column.nullable || column.type == :untyped }
                       .map(&:name)
    unknowable = shapes.filter_map do |shape|
      next unless shape.is_a?(Comparison) && nullable.include?(shape.column)

      value = shape.value
      shape.column unless value.nil? || (value.is_a?(InList) && value.null)
    end
    kept = unknowable.uniq.map { |column| " OR #{qualified(column)} IS NULL" }.join
    [kept.empty? ? "NOT (#{sql})" : "(NOT (#{sql})#{kept})", count]
  end

  # @rbs database: Skyward::ORM::Database
  # @rbs shapes: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def alternative(database, shapes, position)
    sql, count = conjunction(database, shapes, position)
    [shapes.size > 1 ? "(#{sql})" : sql, count]
  end

  # PostgreSQL refuses an empty IN (), and IN never matches NULL.
  # @rbs adapter: Skyward::ORM::_Adapter
  # @rbs name: String
  # @rbs list: InList
  # @rbs position: Integer
  # @rbs return: [String, Integer]
  def within(adapter, name, list, position)
    placeholders = Array.new(list.placeholders) { |index| adapter.placeholder(position + index) }
    listed = "#{name} IN (#{placeholders.join(', ')})"
    sql = if list.placeholders.zero? && !list.null then '1 = 0'
          elsif list.placeholders.zero? then "#{name} IS NULL"
          elsif list.null then "(#{listed} OR #{name} IS NULL)"
          else listed
          end
    [sql, list.placeholders]
  end

  # Steep can't tie the row class to R, so the rows are untyped here and each
  # public method types them.
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: Array[untyped]
  def rows(orders, limit)
    database = @session.database
    # Building the decoder prepares the starting table, once.
    @joins.each { |join| database.prepare(join.table) }
    decode = database.decoder(@table, @row, @expressions.keys)
    sql, binds = statement(database, orders, limit)
    database.execute(sql, binds).map(&decode)
  end

  # @rbs return: Array[singleton(Skyward::ORM::Record)]
  def tables = [@table, *@joins.map(&:table)]

  # A table that's in a query twice needs an alias to tell the two apart,
  # which a query can't give it.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs return: bool
  def present?(table) = tables.any? { |present| present.table_name == table.table_name }

  # @rbs database: Skyward::ORM::Database
  # @rbs return: void
  def prepare(database) = tables.each { |table| database.prepare(table) }

  # Once a query has a join, a column's name could be in more than one table,
  # so each is qualified with its own.
  # @rbs name: Symbol
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs return: String
  def qualified(name, table = @table)
    quoted = Skyward::ORM::Statements.quote(name)
    @joins.empty? ? quoted : "#{Skyward::ORM::Statements.quote(table.table_name)}.#{quoted}"
  end

  # @rbs values: Hash[Symbol, untyped]
  # @rbs returned_row: Class?
  # @rbs return: [String, Array[untyped]]
  def updating(values, returned_row)
    raise ArgumentError, "#{@table} update needs a column to set, such as update(done: true)" if values.empty?

    database = @session.database
    column_types = database.column_types
    Skyward::ORM::Statements.require_values(column_types, database.tables, @table, values)
    columns = values.keys
    set = Skyward::ORM::Statements.binds(database.adapter, column_types, @table, values)
    changing(:update, columns, set, returned_row) do
      assignments = columns.each.with_index(1).map do |column, position|
        "#{Skyward::ORM::Statements.quote(column)} = #{database.adapter.placeholder(position)}"
      end
      "UPDATE #{Skyward::ORM::Statements.quote(@table.table_name)} SET #{assignments.join(', ')}"
    end
  end

  # @rbs returned_row: Class?
  # @rbs return: [String, Array[untyped]]
  def deleting(returned_row)
    changing(:delete, [], [], returned_row) { "DELETE FROM #{Skyward::ORM::Statements.quote(@table.table_name)}" }
  end

  # require_writable leaves a write no clause but its conditions, so they and
  # what it sets and returns are its shape.
  # @rbs method: Symbol
  # @rbs columns: Array[Symbol]
  # @rbs set: Array[untyped]
  # @rbs returned_row: Class?
  # @rbs &: () -> String
  # @rbs return: [String, Array[untyped]]
  def changing(method, columns, set, returned_row)
    require_writable(method)
    database = @session.database
    shapes, binds = bound(database)
    sql = database.cached_sql([method, @table, columns, returned_row, shapes]) do
      where, = filter(database, shapes, set.size + 1)
      [yield, where, (Skyward::ORM::Statements.returning(returned_row) if returned_row)].compact.join(' ')
    end
    [sql, [*set, *binds]]
  end

  # @rbs [T] (T | Skyward::ORM::Violation written) -> T
  def unviolated(written)
    case written
    when Skyward::ORM::Violation then raise Skyward::ORM::ViolationError, written
    else written
    end
  end
end
