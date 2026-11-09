# frozen_string_literal: true

# @rbs generic R < Skyward::ORM::Record
class Skyward::ORM::Query
  include Enumerable #[R]

  # @rbs!
  #   type direction = :asc | :desc

  DIRECTIONS = %i[asc desc].freeze #: Array[direction]

  # @rbs @table: singleton(Skyward::ORM::Record)
  # @rbs @session: Skyward::ORM::Connection::Session
  # @rbs @conditions: Array[[Symbol, untyped]]
  # @rbs @orders: Array[[Symbol, direction]]
  # @rbs @groups: Array[Symbol]

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs session: Skyward::ORM::Connection::Session
  # @rbs conditions: Array[[Symbol, untyped]]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs return: void
  def initialize(table, session, conditions: [], orders: [], groups: [])
    @table = table
    @session = session
    @conditions = [*conditions].freeze
    @orders = [*orders].freeze
    @groups = [*groups].freeze
    freeze
  end

  # @rbs **conditions: untyped
  # @rbs return: Skyward::ORM::Query[R]
  def where(**conditions)
    require_columns(conditions.keys)
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

  # Ordered by the primary key when nothing else orders it, so both databases
  # return the same row.
  # @rbs () -> R?
  #    | (Integer count) -> Array[R]
  def first(count = nil)
    return super if count

    rows(@orders.empty? ? [[@table.schema.primary_key, :asc]] : @orders, " LIMIT 1").first
  end

  # @rbs **conditions: untyped
  # @rbs return: R?
  def find_by(**conditions) = where(**conditions).first

  # PostgreSQL refuses an ORDER BY beside COUNT(*), so the count leaves it out.
  # @rbs (*untyped args) ?{ (R) -> boolish } -> Integer
  def count(*args, &block)
    return super if block || !args.empty?

    database = @session.database
    database.prepare(@table)
    sql, binds = from(database)
    counted = @groups.empty? ? sql : %(FROM (SELECT 1 #{sql}) AS "grouped")
    database.execute("SELECT COUNT(*) #{counted}", binds).fetch(0).fetch(0)
  end

  # @rbs () { (R) -> void } -> self
  #    | () -> Enumerator[R, self]
  def each(&block)
    return enum_for(:each) unless block

    rows(@orders).each(&block)
    self
  end

  # @rbs return: [String, Array[untyped]]
  def to_sql = statement(@session.database, @orders)

  private

  # @rbs conditions: Array[[Symbol, untyped]]
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs groups: Array[Symbol]
  # @rbs return: Skyward::ORM::Query[R]
  def with(conditions: @conditions, orders: @orders, groups: @groups)
    Skyward::ORM::Query.new(@table, @session, conditions:, orders:, groups:)
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

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs return: [String, Array[untyped]]
  def statement(database, orders)
    sql, binds = from(database)
    columns = @table.schema.columns.map { |column| quote(column) }.join(", ")
    ordered = orders.map { |column, direction| "#{quote(column)} #{direction.upcase}" }.join(", ")
    ["SELECT #{columns} #{sql}#{" ORDER BY #{ordered}" unless orders.empty?}", binds]
  end

  # @rbs database: Skyward::ORM::Connection::Database
  # @rbs return: [String, Array[untyped]]
  def from(database)
    none = [[], []] #: [Array[String], Array[untyped]]
    clauses, binds = @conditions.reduce(none) do |(sqls, values), (column, value)|
      sql, bound = condition(database, quote(column), value, values.size + 1)
      [[*sqls, sql], [*values, *bound]]
    end
    sql = [
      "FROM #{quote(@table.table_name)}",
      ("WHERE #{clauses.join(" AND ")}" unless clauses.empty?),
      ("GROUP BY #{@groups.map { |column| quote(column) }.join(", ")}" unless @groups.empty?)
    ].compact.join(" ")
    [sql, binds]
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

  # Steep can't tie a table class to R, so the rows are untyped here and each
  # public method types them.
  # @rbs orders: Array[[Symbol, direction]]
  # @rbs limit: String
  # @rbs return: Array[untyped]
  def rows(orders, limit = "")
    database = @session.database
    sql, binds = statement(database, orders)
    database.execute("#{sql}#{limit}", binds).map(&database.decoder(@table, @table))
  end

  # Quoted, so a column named order or user is still a column.
  # @rbs name: Symbol
  # @rbs return: String
  def quote(name) = %("#{name.name.gsub('"', '""')}")
end
