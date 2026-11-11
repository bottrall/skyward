# frozen_string_literal: true

class Skyward::ORM::Tables::ColumnTypes
  # @rbs @reader: Skyward::Core::Types::Reader
  # @rbs @resolved: Hash[Class, Array[Skyward::ORM::Tables::Column]]

  UNTYPED = Skyward::Core::Types::Scalar.new(name: :untyped) #: Skyward::Core::Types::Scalar

  DECIMAL = Skyward::Core::Types::Scalar.new(name: :decimal) #: Skyward::Core::Types::Scalar

  COLUMN_TYPES = "A column is Integer, Float, String, bool, Date, Time, uuid, int32, int16, a union of symbols " \
                 "or Hash[String, untyped], any of them nullable, or untyped." #: String

  # The aliases Skyward ORM declares, for its reader to keep as the column type each names.
  REFINEMENTS = {
    "::Skyward::ORM::uuid" => :uuid,
    "::Skyward::ORM::int32" => :int32,
    "::Skyward::ORM::int16" => :int16
  }.freeze #: Hash[String, Skyward::ORM::Tables::refinement]

  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: void
  def initialize(reader)
    @reader = reader
    @resolved = {}
  end

  # A class's types are resolved once for the signatures the reader loaded, so
  # no query reads RBS.
  # @rbs klass: Class
  # @rbs return: Array[Skyward::ORM::Tables::Column]
  def columns(klass) = @resolved[klass] ||= resolve(klass)

  private

  # @rbs klass: Class
  # @rbs return: Array[Skyward::ORM::Tables::Column]
  def resolve(klass)
    type_name = @reader.type_name(klass)
    Skyward::ORM::Tables::Members.of(klass).map do |name|
      returned = @reader.method_type(type_name, name)&.type&.return_type if type_name
      written = returned.to_s.gsub(/(?<!\w)::/, "")
      column = returned ? read(name, returned, written) : column(name, UNTYPED, written)
      case column
      when String then raise Skyward::Core::BootError, "#{klass}##{name} #{column}"
      else column
      end
    end.freeze
  end

  # @rbs name: Symbol
  # @rbs returned: RBS::Types::t
  # @rbs written: String
  # @rbs return: Skyward::ORM::Tables::Column | String
  def read(name, returned, written)
    column(name, @reader.read(returned), written)
  # The reader raises for a type it can't read at all, such as one that refers
  # to itself, and the column should still be named.
  rescue Skyward::Core::BootError => e
    "is #{written}. #{e.message}"
  end

  # @rbs name: Symbol
  # @rbs read: Skyward::Core::Types::result
  # @rbs written: String
  # @rbs return: Skyward::ORM::Tables::Column | String
  def column(name, read, written)
    nullable = read.is_a?(Skyward::Core::Types::Nullable)
    carried = read.is_a?(Skyward::Core::Types::Nullable) ? read.type : read
    case carried
    when DECIMAL, Skyward::Core::Types::Record, Skyward::Core::Types::Named, Skyward::Core::Types::ArrayOf
      "is #{written}, which isn't a column type yet. #{COLUMN_TYPES}"
    when Skyward::Core::Types::HashOf
      if carried.type == UNTYPED
        Skyward::ORM::Tables::Column.new(name:, type: :json, nullable:, symbols: [])
      else
        "is #{written}, which isn't a column type. A Hash column is Hash[String, untyped], holding any JSON."
      end
    when Skyward::Core::Types::Scalar
      Skyward::ORM::Tables::Column.new(name:, type: carried.name, nullable:, symbols: [])
    when Skyward::Core::Types::Enum
      Skyward::ORM::Tables::Column.new(name:, type: :enum, nullable:, symbols: carried.symbols)
    when Skyward::Core::Types::Refined
      # The reader refines only the aliases in REFINEMENTS.
      type = carried.as #: Skyward::ORM::Tables::refinement
      Skyward::ORM::Tables::Column.new(name:, type:, nullable:, symbols: [])
    when Skyward::Core::Types::Unreadable
      "can't be read: Skyward ORM doesn't read #{carried.type}#{", at #{carried.at}" if carried.at}. #{COLUMN_TYPES}"
    else "is #{written}, which isn't a column type. #{COLUMN_TYPES}"
    end
  end
end
