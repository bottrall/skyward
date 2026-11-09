# frozen_string_literal: true

# @rbs generic R
class Skyward::ORM::Query
  include Enumerable #[R]

  # @rbs!
  #   type direction = :asc | :desc
  #   type condition = Comparison | Fragment | Negation | Disjunction

  DIRECTIONS = %i[asc desc].freeze #: Array[direction]

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

  # @rbs @table: singleton(Skyward::ORM::Record)
  # @rbs @session: Skyward::ORM::Connection::Session
  # @rbs @joins: Array[Join]
  # @rbs @row: Class
  # @rbs @expressions: Hash[Symbol, String]
  # @rbs @all: bool
  # @rbs @conditions: Array[condition]
  # @rbs @orders: Array[[Symbol, direction]]
  # @rbs @groups: Array[Symbol]
  # @rbs @limit: Integer?
  # @rbs @offset: Integer?

  # all: is true only for an explicit Todo.all, which may update or delete
  # every row.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs joins: Array[Join]
  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs all: bool
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
    all: false,
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
    @all = all
    @conditions = [*conditions].freeze
    @orders = [*orders].freeze
    @groups = [*groups].freeze
    @limit = limit
    @offset = offset
    freeze
  end

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: Skyward::ORM::Query[R]
  def join(table, **on) = joined("JOIN", table, on)

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs **on: Symbol
  # @rbs return: Skyward::ORM::Query[R]
  def left_join(table, **on) = joined("LEFT JOIN", table, on)

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[R]
  def where(sql = nil, *values, **conditions)
    with(all: false, conditions: [*@conditions, *build(sql, values, conditions)])
  end

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[R]
  def exclude(sql = nil, *values, **conditions)
    built = build(sql, values, conditions)
    with(all: false, conditions: built.empty? ? @conditions : [*@conditions, Negation.new(conditions: built)])
  end

  # @rbs sql: String?
  # @rbs *values: untyped
  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[R]
  def or(sql = nil, *values, **conditions)
    raise ArgumentError, "#{@table} has no conditions to or with. Start with where or exclude." if @conditions.empty?

    built = build(sql, values, conditions)
    raise ArgumentError, "#{@table} has nothing to or with. Give or conditions or SQL." if built.empty?

    with(conditions: [Disjunction.new(left: @conditions, right: built)])
  end

  # @rbs *columns: Symbol
  # @rbs **directions: direction
  # @rbs return: Skyward::ORM::Query[R]
  def order(*columns, **directions)
    Skyward::ORM::Statements.require_columns(@table, [*columns, *directions.keys])
    # The direction is written into the SQL, so only these two may reach it.
    column, direction = directions.find { |_, candidate| !DIRECTIONS.include?(candidate) }
    raise ArgumentError, "#{@table} can't order #{column} by #{direction.inspect}, only :asc or :desc" if column

    with(orders: [*@orders, *columns.map { |name| [name, :asc] }, *directions.to_a])
  end

  # @rbs *columns: Symbol
  # @rbs return: Skyward::ORM::Query[R]
  def group(*columns)
    Skyward::ORM::Statements.require_columns(@table, columns)
    with(groups: [*@groups, *columns])
  end

  # @rbs count: Integer
  # @rbs return: Skyward::ORM::Query[R]
  def limit(count) = with(limit: require_count(:limit, count))

  # @rbs count: Integer
  # @rbs return: Skyward::ORM::Query[R]
  def offset(count) = with(offset: require_count(:offset, count))

  # Steep ties the row class to S only through its new, so the query keeps it
  # as the Class it is.
  # @rbs [S] (Skyward::ORM::_Row[S] row, **String expressions) -> Skyward::ORM::Query[S]
  def into(row, **expressions)
    klass = row #: Class
    require_members(klass, expressions)
    with(row: klass, expressions:)
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
    sql, binds = from(database, [], @limit)
    counted = @groups.empty? && @limit.nil? && @offset.nil? ? sql : %(FROM (SELECT 1 #{sql}) AS "counted")
    database.execute("SELECT COUNT(*) #{counted}", binds).fetch(0).fetch(0)
  end

  # Order can't change whether the query has a row, so it's left out, and a
  # limit of 0 has none.
  # @rbs return: bool
  def exists?
    database = @session.database
    prepare(database)
    sql, binds = from(database, [], [@limit, 1].compact.min)
    !database.execute("SELECT 1 #{sql}", binds).empty?
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

  # @rbs **values: untyped
  # @rbs return: Array[R] | Skyward::ORM::Violation
  def update(**values)
    raise ArgumentError, "#{@table} update needs a column to set, such as update(done: true)" if values.empty?

    database = @session.database
    Skyward::ORM::Statements.require_values(database.column_types, @table, values)
    assignments = values.keys.each.with_index(1).map do |column, position|
      "#{Skyward::ORM::Statements.quote(column)} = #{database.adapter.placeholder(position)}"
    end
    write(
      :update,
      "UPDATE #{Skyward::ORM::Statements.quote(@table.table_name)} SET #{assignments.join(", ")}",
      values.values
    )
  end

  # @rbs **values: untyped
  # @rbs return: Array[R]
  def update!(**values) = unviolated(update(**values))

  # @rbs return: Array[R]
  def delete! = unviolated(write(:delete!, "DELETE FROM #{Skyward::ORM::Statements.quote(@table.table_name)}", []))

  private

  # @rbs joins: Array[Join]
  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs all: bool
  # @rbs conditions: Array[condition]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs limit: Integer?
  # @rbs offset: Integer?
  # @rbs return: Skyward::ORM::Query[untyped]
  def with(
    joins: @joins,
    row: @row,
    expressions: @expressions,
    all: @all,
    conditions: @conditions,
    orders: @orders,
    groups: @groups,
    limit: @limit,
    offset: @offset
  )
    Skyward::ORM::Query.new(
      @table,
      @session,
      joins:,
      row:,
      expressions:,
      all:,
      conditions:,
      orders:,
      groups:,
      limit:,
      offset:
    )
  end

  # @rbs keyword: String
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs on: Hash[Symbol, Symbol]
  # @rbs return: Skyward::ORM::Query[R]
  def joined(keyword, table, on)
    unless table.is_a?(Class) && table < Skyward::ORM::Record && table.schema.table
      raise ArgumentError, "#{@table} can't join #{table.inspect}, which isn't a table class"
    end
    # A table that's in a query twice needs an alias to tell the two apart,
    # which a query can't give it.
    if tables.any? { |present| present.table_name == table.table_name }
      raise ArgumentError, "#{@table} can't join #{table}, since #{table.table_name} is already in the query"
    end
    raise ArgumentError, "#{@table} can't join #{table} on nothing. Give it columns, such as list_id: :id" if on.empty?

    Skyward::ORM::Statements.require_columns(@table, on.keys)
    Skyward::ORM::Statements.require_columns(table, on.values)
    with(joins: [*@joins, Join.new(keyword:, table:, on:)])
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
    return [Comparison.new(column:, operator: "=", value:)] unless value.is_a?(Range)

    ends = [
      (Comparison.new(column:, operator: ">=", value: value.begin) unless value.begin.nil?),
      (Comparison.new(column:, operator: value.exclude_end? ? "<" : "<=", value: value.end) unless value.end.nil?)
    ].compact
    raise ArgumentError, "#{@table} can't match #{column} to #{value.inspect}, a range with neither end" if ends.empty?

    ends
  end

  # Neither PostgreSQL nor SQLite (as it's usually built) takes a JOIN,
  # ORDER BY, GROUP BY, LIMIT or OFFSET on an UPDATE or DELETE, and an into
  # expression, such as an aggregate, means nothing portable in its RETURNING.
  # @rbs method: Symbol
  # @rbs return: void
  def require_writable(method)
    clauses = [
      ("into expressions" unless @expressions.empty?),
      ("join" unless @joins.empty?),
      ("order" unless @orders.empty?),
      ("group" unless @groups.empty?),
      ("limit" if @limit),
      ("offset" if @offset)
    ].compact
    unless clauses.empty?
      *others, last = clauses
      listed = others.empty? ? last : "#{others.join(", ")} or #{last}"
      raise ArgumentError,
            "#{@table} can't #{method} a query with #{listed}, which PostgreSQL and SQLite don't both support"
    end
    return unless @conditions.empty? && !@all

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
    members = Skyward::ORM::Members.of(row)
    unknown = expressions.keys - members
    raise ArgumentError, "#{row} has no member #{unknown.join(", ")} to take an expression" unless unknown.empty?

    unread = members - @table.schema.columns - expressions.keys
    return if unread.empty?

    raise ArgumentError, "#{@table} has no column #{unread.join(", ")}, so #{row} needs an expression for it"
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: [String, Array[untyped]]
  def statement(database, orders, limit)
    sql, binds = from(database, orders, limit)
    columns = Skyward::ORM::Members.of(@row).map do |member|
      expression = @expressions.fetch(member, nil)
      expression ? "#{expression} AS #{Skyward::ORM::Statements.quote(member)}" : qualified(member)
    end.join(", ")
    ["SELECT #{columns} #{sql}", binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: [String, Array[untyped]]
  def from(database, orders, limit)
    adapter = database.adapter
    where, binds = filter(database, 1)
    ordered = orders.map { |column, direction| "#{qualified(column)} #{direction.upcase}" }
    # The limit and offset are bound rather than written in, so every page of a
    # query shares one SQL string.
    paging = [limit, @offset].compact
    sql = [
      "FROM #{Skyward::ORM::Statements.quote(@table.table_name)}",
      *@joins.map { |join| joining(join) },
      where,
      ("GROUP BY #{@groups.map { |column| qualified(column) }.join(", ")}" unless @groups.empty?),
      ("ORDER BY #{ordered.join(", ")}" unless orders.empty?),
      limit ? "LIMIT #{adapter.placeholder(binds.size + 1)}" : (adapter.unlimited if @offset),
      ("OFFSET #{adapter.placeholder(binds.size + paging.size)}" if @offset)
    ].compact.join(" ")
    [sql, [*binds, *paging]]
  end

  # @rbs join: Join
  # @rbs return: String
  def joining(join)
    on = join.on.map { |column, joined| "#{qualified(column)} = #{qualified(joined, join.table)}" }.join(" AND ")
    "#{join.keyword} #{Skyward::ORM::Statements.quote(join.table.table_name)} ON #{on}"
  end

  # An UPDATE binds its SET values first, so its WHERE's numbered placeholders
  # start after them.
  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs position: Integer
  # @rbs return: [String?, Array[untyped]]
  def filter(database, position)
    clauses, binds = conjunction(database, @conditions, position)
    [("WHERE #{clauses}" unless @conditions.empty?), binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs conditions: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def conjunction(database, conditions, position)
    none = [[], []] #: [Array[String], Array[untyped]]
    clauses, binds = conditions.reduce(none) do |(sqls, values), condition|
      sql, bound = render(database, condition, position + values.size)
      [[*sqls, condition.is_a?(Disjunction) && conditions.size > 1 ? "(#{sql})" : sql], [*values, *bound]]
    end
    [clauses.join(" AND "), binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs condition: condition
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def render(database, condition, position)
    case condition
    when Comparison then comparison(database, condition, position)
    when Fragment then fragment(database, condition, position)
    when Negation then negation(database, condition.conditions, position)
    when Disjunction
      left, left_binds = alternative(database, condition.left, position)
      right, right_binds = alternative(database, condition.right, position + left_binds.size)
      ["#{left} OR #{right}", [*left_binds, *right_binds]]
    end
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs comparison: Comparison
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def comparison(database, comparison, position)
    name = qualified(comparison.column)
    value = comparison.value
    case value
    when nil then ["#{name} IS NULL", []]
    when Array then within(database, name, value, position)
    else ["#{name} #{comparison.operator} #{database.adapter.placeholder(position)}", [database.adapter.encode(value)]]
    end
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs fragment: Fragment
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def fragment(database, fragment, position)
    adapter = database.adapter
    binds = fragment.values.map { |value| adapter.encode(value) }
    Skyward::ORM::Placeholders.require_scalars(binds, "An SQL condition")
    sql = Skyward::ORM::Placeholders.replace(fragment.sql, binds.size) do |index|
      adapter.placeholder(position + index - 1)
    end
    # A -- comment runs to the end of its line, so the closing parenthesis
    # goes on a line of its own.
    ["(#{sql}#{"\n" if sql.include?("--")})", binds]
  end

  # NOT of an unknown is unknown, so a row whose column is NULL would be left
  # out, though it doesn't match. An untyped column may hold NULL, and an SQL
  # string's columns can't be known.
  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs conditions: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def negation(database, conditions, position)
    sql, binds = conjunction(database, conditions, position)
    nullable = database.column_types.columns(@table).select { |column| column.nullable || column.type == :untyped }
                       .map(&:name)
    unknowable = conditions.filter_map do |condition|
      next unless condition.is_a?(Comparison) && nullable.include?(condition.column)

      value = condition.value
      condition.column unless value.nil? || (value.is_a?(Array) && value.include?(nil))
    end
    kept = unknowable.uniq.map { |column| " OR #{qualified(column)} IS NULL" }.join
    [kept.empty? ? "NOT (#{sql})" : "(NOT (#{sql})#{kept})", binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs conditions: Array[condition]
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def alternative(database, conditions, position)
    sql, binds = conjunction(database, conditions, position)
    [conditions.size > 1 ? "(#{sql})" : sql, binds]
  end

  # PostgreSQL refuses an empty IN (), and IN never matches NULL.
  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs name: String
  # @rbs values: Array[untyped]
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def within(database, name, values, position)
    present = values.compact
    placeholders = Array.new(present.size) { |index| database.adapter.placeholder(position + index) }
    list = "#{name} IN (#{placeholders.join(", ")})"
    sql = if values.empty? then "1 = 0"
          elsif present.empty? then "#{name} IS NULL"
          elsif values.include?(nil) then "(#{list} OR #{name} IS NULL)"
          else list
          end
    [sql, present.map { |value| database.adapter.encode(value) }]
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

  # @rbs database: Skyward::ORM::Connection::Database
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

  # @rbs method: Symbol
  # @rbs sql: String
  # @rbs values: Array[untyped]
  # @rbs return: Array[untyped] | Skyward::ORM::Violation
  def write(method, sql, values)
    require_writable(method)
    database = @session.database
    where, binds = filter(database, values.size + 1)
    database.write(
      @table,
      @row,
      [sql, where, Skyward::ORM::Statements.returning(Skyward::ORM::Members.of(@row))].compact.join(" "),
      [*values.map { |value| database.adapter.encode(value) }, *binds]
    )
  end

  # @rbs written: Array[untyped] | Skyward::ORM::Violation
  # @rbs return: Array[untyped]
  def unviolated(written)
    case written
    when Skyward::ORM::Violation then raise Skyward::ORM::ViolationError, written
    else written
    end
  end
end
