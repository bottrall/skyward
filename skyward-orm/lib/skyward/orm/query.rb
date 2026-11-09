# frozen_string_literal: true

# @rbs generic R
class Skyward::ORM::Query
  include Enumerable #[R]

  # @rbs!
  #   type direction = :asc | :desc

  DIRECTIONS = %i[asc desc].freeze #: Array[direction]

  # @rbs @table: singleton(Skyward::ORM::Record)
  # @rbs @session: Skyward::ORM::Connection::Session
  # @rbs @row: Class
  # @rbs @expressions: Hash[Symbol, String]
  # @rbs @conditions: Array[[Symbol, untyped]]
  # @rbs @orders: Array[[Symbol, direction]]
  # @rbs @groups: Array[Symbol]
  # @rbs @limit: Integer?
  # @rbs @offset: Integer?

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs conditions: Array[[Symbol, untyped]]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs limit: Integer?
  # @rbs offset: Integer?
  # @rbs return: void
  def initialize(
    table,
    session,
    row: table,
    expressions: {},
    conditions: [],
    orders: [],
    groups: [],
    limit: nil,
    offset: nil
  )
    @table = table
    @session = session
    @row = row
    @expressions = expressions.dup.freeze
    @conditions = [*conditions].freeze
    @orders = [*orders].freeze
    @groups = [*groups].freeze
    @limit = limit
    @offset = offset
    freeze
  end

  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[R]
  def where(**conditions)
    require_columns(conditions.keys)
    require_types(conditions)
    with(conditions: [*@conditions, *conditions.to_a])
  end

  # @rbs *columns: Symbol
  # @rbs **directions: direction
  # @rbs return: Skyward::ORM::Query[R]
  def order(*columns, **directions)
    require_columns([*columns, *directions.keys])
    # The direction is written into the SQL, so only these two may reach it.
    column, direction = directions.find { |_, candidate| !DIRECTIONS.include?(candidate) }
    raise ArgumentError, "#{@table} can't order #{column} by #{direction.inspect}, only :asc or :desc" if column

    with(orders: [*@orders, *columns.map { |name| [name, :asc] }, *directions.to_a])
  end

  # @rbs *columns: Symbol
  # @rbs return: Skyward::ORM::Query[R]
  def group(*columns)
    require_columns(columns)
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
    database.prepare(@table)
    sql, binds = from(database, [], @limit)
    counted = @groups.empty? && @limit.nil? && @offset.nil? ? sql : %(FROM (SELECT 1 #{sql}) AS "counted")
    database.execute("SELECT COUNT(*) #{counted}", binds).fetch(0).fetch(0)
  end

  # Order can't change whether the query has a row, so it's left out, and a
  # limit of 0 has none.
  # @rbs return: bool
  def exists?
    database = @session.database
    database.prepare(@table)
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

  private

  # @rbs row: Class
  # @rbs expressions: Hash[Symbol, String]
  # @rbs conditions: Array[[Symbol, untyped]]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs limit: Integer?
  # @rbs offset: Integer?
  # @rbs return: Skyward::ORM::Query[untyped]
  def with(
    row: @row,
    expressions: @expressions,
    conditions: @conditions,
    orders: @orders,
    groups: @groups,
    limit: @limit,
    offset: @offset
  )
    Skyward::ORM::Query.new(@table, @session, row:, expressions:, conditions:, orders:, groups:, limit:, offset:)
  end

  # @rbs columns: Array[Symbol]
  # @rbs return: void
  def require_columns(columns)
    known = @table.schema.columns
    unknown = (columns - known).first #: Symbol?
    return unless unknown

    suggestion = DidYouMean::SpellChecker.new(dictionary: known).correct(unknown).first
    raise ArgumentError, "#{@table} has no column #{unknown}.#{" Did you mean #{suggestion}?" if suggestion}"
  end

  # @rbs conditions: Hash[Symbol, untyped]
  # @rbs return: void
  def require_types(conditions)
    columns = @session.database.column_types.columns(@table).to_h { |column| [column.name, column] }
    mismatch = conditions.filter_map do |name, value|
      Skyward::ORM::Tables::Values.mismatch(@table, columns.fetch(name), value)
    end.first
    raise ArgumentError, mismatch if mismatch
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
      expression ? "#{expression} AS #{quote(member)}" : quote(member)
    end.join(", ")
    ["SELECT #{columns} #{sql}", binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: Integer?
  # @rbs return: [String, Array[untyped]]
  def from(database, orders, limit)
    adapter = database.adapter
    none = [[], []] #: [Array[String], Array[untyped]]
    clauses, binds = @conditions.reduce(none) do |(sqls, values), (column, value)|
      sql, bound = condition(database, quote(column), value, values.size + 1)
      [[*sqls, sql], [*values, *bound]]
    end
    ordered = orders.map { |column, direction| "#{quote(column)} #{direction.upcase}" }.join(", ")
    # The limit and offset are bound rather than written in, so every page of a
    # query shares one SQL string.
    paging = [limit, @offset].compact
    sql = [
      "FROM #{quote(@table.table_name)}",
      ("WHERE #{clauses.join(" AND ")}" unless clauses.empty?),
      ("GROUP BY #{@groups.map { |column| quote(column) }.join(", ")}" unless @groups.empty?),
      ("ORDER BY #{ordered}" unless orders.empty?),
      limit ? "LIMIT #{adapter.placeholder(binds.size + 1)}" : (adapter.unlimited if @offset),
      ("OFFSET #{adapter.placeholder(binds.size + paging.size)}" if @offset)
    ].compact.join(" ")
    [sql, [*binds, *paging]]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs name: String
  # @rbs value: untyped
  # @rbs position: Integer
  # @rbs return: [String, Array[untyped]]
  def condition(database, name, value, position)
    case value
    when nil then ["#{name} IS NULL", []]
    when Array then within(database, name, value, position)
    else ["#{name} = #{database.adapter.placeholder(position)}", [database.adapter.encode(value)]]
    end
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
    decode = database.decoder(@table, @row, @expressions.keys)
    sql, binds = statement(database, orders, limit)
    database.execute(sql, binds).map(&decode)
  end

  # Quoted, so a column named order or user is still a column.
  # @rbs name: Symbol
  # @rbs return: String
  def quote(name) = %("#{name.name.gsub('"', '""')}")
end
