# frozen_string_literal: true

# @rbs module-self Class
module Skyward::ORM::Tables::Declarations
  EMPTY = Skyward::ORM::Tables::Schema.new(
    table: nil,
    primary_key: :id,
    columns: [],
    references: [],
    defaults: {},
    checks: [],
    uniques: [],
    indexes: []
  ) #: Skyward::ORM::Tables::Schema

  ON_DELETE = %i[cascade restrict set_null set_default no_action].freeze #: Array[Skyward::ORM::Tables::on_delete]

  # @rbs @schema: Skyward::ORM::Tables::Schema?
  # @rbs @locations: Hash[[Symbol, Symbol], [String, Integer]]?

  # @rbs return: Skyward::ORM::Tables::Schema
  def schema = @schema || EMPTY

  # The schema is compared as a value, so where each name was declared is kept
  # beside it, by the declaration and the column or table it names.
  # @rbs declaration: Symbol
  # @rbs name: Symbol
  # @rbs return: [String, Integer]?
  def declared_at(declaration, name) = @locations&.[]([declaration, name])

  # @rbs return: Symbol
  def table_name
    schema.table || raise(
      Skyward::Core::BootError,
      Skyward::ORM::Tables::Sources.explain(
        "#{self} has no table. Add `table :name` to its body.",
        [Skyward::ORM::Tables::Sources.class_name(self)]
      )
    )
  end

  # Every attr_reader is a column, so each one compiles the row's methods again.
  # @rbs *names: interned
  # @rbs return: Array[Symbol]
  def attr_reader(*names)
    # Steep doesn't look up super in the Class this module extends.
    readers = super # steep:ignore UnexpectedSuper
    columns = [*schema.columns, *readers]
    repeated = columns.find { |column| columns.count(column) > 1 }
    raise ArgumentError, "#{self} already has a column #{repeated}" if repeated

    declare(:attr_reader, readers, columns: columns.freeze)
    # Ruby warns when a method is redefined, so the old ones are removed first.
    (Skyward::ORM::Tables::Rows::METHODS & [*instance_methods(false), *private_instance_methods(false)])
      .each { |method| remove_method(method) }
    class_eval(Skyward::ORM::Tables::Rows.source(columns), __FILE__, __LINE__)
    readers
  end

  # @rbs name: Symbol
  # @rbs return: void
  def table(name)
    refuse(:table, [name], "the table's name must be a Symbol, such as :todos") unless symbol?(name)
    declare(:table, [name], table: name)
  end

  # @rbs column: Symbol
  # @rbs return: void
  def primary_key(column)
    problem = unnamed([column])
    refuse(:primary_key, [column], problem) if problem
    declare(:primary_key, [column], primary_key: column)
  end

  # @rbs column: Symbol
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs on_delete: Skyward::ORM::Tables::on_delete?
  # @rbs return: void
  def references(column, table, on_delete: nil)
    problem = unnamed([column]) || unreferenceable(table, on_delete)
    refuse(:references, [column], problem) if problem
    reference = Skyward::ORM::Tables::Reference.new(column:, table:, on_delete:)
    declare(:references, [column], references: [*schema.references, reference].freeze)
  end

  # @rbs **values: untyped
  # @rbs return: void
  def default(**values)
    declare(:default, values.keys, defaults: schema.defaults.merge(values).freeze)
  end

  # @rbs *columns: Symbol
  # @rbs return: void
  def unique(*columns)
    problem = unnamed(columns)
    refuse(:unique, columns, problem) if problem
    declare(:unique, columns, uniques: [*schema.uniques, columns.freeze].freeze)
  end

  # @rbs column: Symbol
  # @rbs sql: Skyward::ORM::Tables::SQL?
  # @rbs length: Range[Integer?]?
  # @rbs return: void
  def check(column, sql = nil, length: nil)
    rule = unnamed([column]) || check_rule(sql, length)
    case rule
    when String then refuse(:check, [column], rule)
    else
      declare(:check, [column], checks: [*schema.checks, Skyward::ORM::Tables::Check.new(column:, rule:)].freeze)
    end
  end

  # @rbs *columns: Symbol
  # @rbs return: void
  def index(*columns)
    problem = unnamed(columns)
    refuse(:index, columns, problem) if problem
    declare(:index, columns, indexes: [*schema.indexes, columns.freeze].freeze)
  end

  private

  # Only a declaration calls this, so its caller's caller is the class body.
  # An anonymous class, from Class.new, keeps no location, and eval'd code has
  # no file to point at.
  # @rbs declaration: Symbol
  # @rbs names: Array[Symbol]
  # @rbs **changes: untyped
  # @rbs return: void
  def declare(declaration, names, **changes)
    @schema = schema.with(**changes)
    site = caller_locations(2, 1)&.first
    path = site&.absolute_path
    return unless name && site && path

    located = names.to_h do |named|
      [[declaration, named], [path, site.lineno]] #: [[Symbol, Symbol], [String, Integer]]
    end
    @locations = (@locations || {}).merge(located)
  end

  # @rbs declaration: Symbol
  # @rbs arguments: Array[untyped]
  # @rbs problem: String
  # @rbs return: bot
  def refuse(declaration, arguments, problem)
    raise ArgumentError, "#{self} #{"#{declaration} #{arguments.map(&:inspect).join(", ")}".rstrip}: #{problem}"
  end

  # @rbs value: untyped
  # @rbs return: bool
  def symbol?(value) = value.is_a?(Symbol)

  # @rbs columns: Array[untyped]
  # @rbs return: String?
  def unnamed(columns)
    if columns.empty? then "it needs at least one column"
    elsif !columns.all?(Symbol) then "a column's name must be a Symbol, such as :title"
    end
  end

  # @rbs table: untyped
  # @rbs on_delete: untyped
  # @rbs return: String?
  def unreferenceable(table, on_delete)
    if !table.is_a?(Class) || !(table < Skyward::ORM::Record)
      "it references #{table.inspect}, which isn't a table class"
    elsif !on_delete.nil? && !ON_DELETE.include?(on_delete)
      "on_delete: is #{on_delete.inspect}, but it can only be :#{ON_DELETE.join(", :")} or nil"
    end
  end

  # @rbs sql: untyped
  # @rbs length: untyped
  # @rbs return: Skyward::ORM::Tables::SQL | Skyward::ORM::Tables::Length | String
  def check_rule(sql, length)
    if sql && length then "it takes Skyward.sql(\"...\") or length:, not both"
    elsif sql.is_a?(Skyward::ORM::Tables::SQL) then sql
    elsif sql.is_a?(String) then "write the SQL as Skyward.sql(#{sql.inspect}), not a plain String"
    elsif sql then "it takes Skyward.sql(\"...\") or length:, not #{sql.inspect}"
    elsif length.nil? then "it needs Skyward.sql(\"...\") or length:"
    else length_rule(length)
    end
  end

  # @rbs range: untyped
  # @rbs return: Skyward::ORM::Tables::Length | String
  def length_rule(range)
    unless range.is_a?(Range) && [range.begin, range.end].compact.all?(Integer)
      return "length: must be a Range of Integers, such as 1..200, not #{range.inspect}"
    end

    min = range.begin
    max = range.exclude_end? && range.end ? range.end - 1 : range.end
    if min.nil? && max.nil? then "length: #{range.inspect} needs a bound, such as 1..200"
    elsif min && max && min > max then "length: #{range.inspect} is empty"
    else Skyward::ORM::Tables::Length.new(min:, max:)
    end
  end
end
