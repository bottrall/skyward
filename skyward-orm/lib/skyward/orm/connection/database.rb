# frozen_string_literal: true

class Skyward::ORM::Connection::Database
  # @rbs @adapter: Skyward::ORM::_Adapter
  # @rbs @connection: Skyward::ORM::_Connection
  # @rbs @column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs @tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs @check: bool
  # @rbs @checked: Set[singleton(Skyward::ORM::Record)]
  # @rbs @lock: Thread::Mutex
  # @rbs @decoders: Hash[[singleton(Skyward::ORM::Record), singleton(Skyward::ORM::Record)], ^(Array[untyped]) -> Skyward::ORM::Record]

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection,
  #   Skyward::ORM::Tables::ColumnTypes column_types, Array[Skyward::ORM::Catalog::Table] tables, check: bool) -> void
  def initialize(adapter, connection, column_types, tables, check:)
    @adapter = adapter
    @connection = connection
    @column_types = column_types
    @tables = tables
    @check = check
    @checked = Set.new
    @lock = Thread::Mutex.new
    @decoders = {}
  end

  # @dynamic adapter
  attr_reader :adapter #: Skyward::ORM::_Adapter

  # @dynamic column_types
  attr_reader :column_types #: Skyward::ORM::Tables::ColumnTypes

  # @dynamic tables
  attr_reader :tables #: Array[Skyward::ORM::Catalog::Table]

  # @rbs sql: String
  # @rbs return: Array[Array[untyped]]
  def execute(sql) = @connection.execute(sql)

  # @rbs tables: Array[singleton(Skyward::ORM::Record)]
  # @rbs return: void
  def check(tables)
    @lock.synchronize do
      unchecked = tables.reject { |table| @checked.include?(table) }
      unchecked.each { |table| Skyward::ORM::Tables::Validation.validate(table) }
      mismatches = unchecked.filter_map do |table|
        SchemaCheck.mismatch(table, @column_types.columns(table), @tables, @adapter)
      end
      raise Skyward::ORM::SchemaMismatch, mismatches.join("\n\n") unless mismatches.empty?

      @checked.merge(unchecked)
    end
  end

  # A query selects its row class's columns in order, so the decoder reads
  # each value by position, as its table's column type says.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: singleton(Skyward::ORM::Record)
  # @rbs return: ^(Array[untyped]) -> Skyward::ORM::Record
  def decoder(table, row) = @decoders[[table, row]] ||= build(table, row)

  # @rbs error: StandardError
  # @rbs table: Symbol
  # @rbs return: Skyward::ORM::Violation?
  def violation(error, table) = @adapter.violation(error, @tables, table)

  private

  # Every query and write decodes through here, so a table class loaded after
  # connect is checked before its first use.
  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: singleton(Skyward::ORM::Record)
  # @rbs return: ^(Array[untyped]) -> Skyward::ORM::Record
  def build(table, row)
    check([table]) if @check
    columns = @column_types.columns(table).to_h { |column| [column.name, column.type] }
    members = row.schema.columns
    types = members.map { |member| columns[member] || :untyped } #: Array[Skyward::ORM::Tables::column_type]
    lambda do |values|
      row.new(
        **members.each_with_index.to_h do |member, index|
          value = values.fetch(index)
          [member, value.nil? ? nil : @adapter.decode(types.fetch(index), value)]
        end
      )
    end
  end
end
