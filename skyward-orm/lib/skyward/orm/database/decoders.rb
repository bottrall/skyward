# frozen_string_literal: true

module Skyward::ORM::Database::Decoders
  extend self

  # @rbs (Class row, Array[Skyward::ORM::Tables::Column] columns, Array[Integer] positions,
  #   Skyward::ORM::_Adapter adapter) -> ^(Array[untyped]) -> untyped
  def compile(row, columns, positions, adapter)
    # Evaluated in the row class, so the lambda calls its new or allocate.
    row.instance_eval(source(row, columns, positions, adapter), __FILE__, __LINE__)
  end

  private

  # @rbs (Class row, Array[Skyward::ORM::Tables::Column] columns, Array[Integer] positions,
  #   Skyward::ORM::_Adapter adapter) -> String
  def source(row, columns, positions, adapter)
    values = columns.each_with_index.map do |column, index|
      value = "value#{index}"
      # Only names go into the source, and the adapter's own decodings.
      "(#{value} = values[#{positions.fetch(index)}]).nil? ? nil : #{adapter.decoding(column, value)}"
    end
    # Without it, each String literal a decoding writes would allocate for every row.
    "# frozen_string_literal: true\n->(values) { #{construction(row, columns, values)} }"
  end

  # @rbs row: Class
  # @rbs columns: Array[Skyward::ORM::Tables::Column]
  # @rbs values: Array[String]
  # @rbs return: String
  def construction(row, columns, values)
    # A table class's own initialize checks the columns it's given, which the
    # source already guarantees, so its row is loaded directly.
    if row.instance_method(:initialize).owner == Skyward::ORM::Record
      "allocate.__send__(:load_columns, #{values.join(', ')})"
    else
      # A member's name as a quoted label, such as "end":, names any Symbol.
      "new(#{columns.zip(values).map { |column, value| "#{column.name.name.inspect}: #{value}" }.join(', ')})"
    end
  end
end
