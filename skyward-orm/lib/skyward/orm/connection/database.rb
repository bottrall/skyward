# frozen_string_literal: true

class Skyward::ORM::Connection::Database
  # @rbs @adapter: Skyward::ORM::_Adapter
  # @rbs @connection: Skyward::ORM::_Connection
  # @rbs @column_types: Skyward::ORM::Tables::ColumnTypes
  # @rbs @tables: Array[Skyward::ORM::Catalog::Table]
  # @rbs @decoders: Hash[[singleton(Skyward::ORM::Record), singleton(Skyward::ORM::Record)], ^(Array[untyped]) -> Skyward::ORM::Record]

  # @rbs (Skyward::ORM::_Adapter adapter, Skyward::ORM::_Connection connection,
  #   Skyward::ORM::Tables::ColumnTypes column_types, Array[Skyward::ORM::Catalog::Table] tables) -> void
  def initialize(adapter, connection, column_types, tables)
    @adapter = adapter
    @connection = connection
    @column_types = column_types
    @tables = tables
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

  # @rbs table: singleton(Skyward::ORM::Record)
  # @rbs row: singleton(Skyward::ORM::Record)
  # @rbs return: ^(Array[untyped]) -> Skyward::ORM::Record
  def build(table, row)
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
