# frozen_string_literal: true

class Skyward::ORM::Tables::ColumnTypes
  # @rbs @reader: Skyward::Core::Types::Reader
  # @rbs @resolved: Hash[Class, Array[Skyward::ORM::Tables::Column]]

  UNTYPED = Skyward::Core::Types::Scalar.new(name: :untyped) #: Skyward::Core::Types::Scalar

  COLUMN_TYPES = 'A column is Integer, Float, BigDecimal, String, bool, Date, Time, uuid, int32, int16, ' \
                 'a union of symbols, Hash[String, untyped] or Array[T], any of them nullable, or untyped.' #: String

  ELEMENTS = %i[integer float decimal string bool date time].freeze #: Array[Skyward::Core::Types::scalar]

  ELEMENT_TYPES = 'An Array column is Array[T], where T is Integer, Float, BigDecimal, String, bool, Date, Time ' \
                  "or a union of symbols, and isn't nullable." #: String

  # The aliases Skyward ORM declares, for its reader to keep as the column type each names.
  REFINEMENTS = {
    '::Skyward::ORM::uuid' => :uuid,
    '::Skyward::ORM::int32' => :int32,
    '::Skyward::ORM::int16' => :int16
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
      written = returned.to_s.gsub(/(?<!\w)::/, '')
      column = returned ? read(name, returned, written) : column(name, UNTYPED, written)
      case column
      when Skyward::ORM::Tables::Column then column
      else
        problem, suggestion = column
        spot = Skyward::ORM::Tables::Sources.reader(klass, name)
        raise Skyward::Core::BootError,
              Skyward::ORM::Tables::Sources.explain("#{klass}##{name} #{problem}", [spot], suggestion)
      end
    end.freeze
  end

  # @rbs name: Symbol
  # @rbs returned: RBS::Types::t
  # @rbs written: String
  # @rbs return: Skyward::ORM::Tables::Column | [String, String?]
  def read(name, returned, written)
    column(name, @reader.read(returned), written)
  # The reader raises for a type it can't read at all, such as one that refers
  # to itself, and the column should still be named.
  rescue Skyward::Core::BootError => e
    ["is #{written}. #{e.message}", nil]
  end

  # @rbs name: Symbol
  # @rbs read: Skyward::Core::Types::result
  # @rbs written: String
  # @rbs return: Skyward::ORM::Tables::Column | [String, String?]
  def column(name, read, written)
    nullable = read.is_a?(Skyward::Core::Types::Nullable)
    carried = read.is_a?(Skyward::Core::Types::Nullable) ? read.type : read
    case carried
    when Skyward::Core::Types::Record, Skyward::Core::Types::Named
      ["is #{written}, which isn't a column type yet. #{COLUMN_TYPES}", nil]
    when Skyward::Core::Types::ArrayOf then array(name, carried.type, nullable, written)
    when Skyward::Core::Types::HashOf
      if carried.type == UNTYPED
        Skyward::ORM::Tables::Column.new(name:, type: :json, nullable:, symbols: [], element: nil)
      else
        ["is #{written}, which isn't a column type. A Hash column is Hash[String, untyped], holding any JSON.", nil]
      end
    when Skyward::Core::Types::Scalar
      Skyward::ORM::Tables::Column.new(name:, type: carried.name, nullable:, symbols: [], element: nil)
    when Skyward::Core::Types::Enum
      Skyward::ORM::Tables::Column.new(name:, type: :enum, nullable:, symbols: carried.symbols, element: nil)
    when Skyward::Core::Types::Refined
      # The reader refines only the aliases in REFINEMENTS.
      type = carried.as #: Skyward::ORM::Tables::refinement
      Skyward::ORM::Tables::Column.new(name:, type:, nullable:, symbols: [], element: nil)
    when Skyward::Core::Types::Unreadable
      at = ", at #{carried.at}" if carried.at
      ["can't be read: Skyward ORM doesn't read #{carried.type}#{at}. #{COLUMN_TYPES}", carried.suggestion]
    else ["is #{written}, which isn't a column type. #{COLUMN_TYPES}", nil]
    end
  end

  # @rbs name: Symbol
  # @rbs item: Skyward::Core::Types::t
  # @rbs nullable: bool
  # @rbs written: String
  # @rbs return: Skyward::ORM::Tables::Column | [String, String?]
  def array(name, item, nullable, written)
    case item
    when Skyward::Core::Types::Scalar
      if ELEMENTS.include?(item.name)
        Skyward::ORM::Tables::Column.new(name:, type: :array, nullable:, symbols: [], element: item.name)
      else
        ["is #{written}, which isn't a column type. #{ELEMENT_TYPES}", nil]
      end
    when Skyward::Core::Types::Enum
      Skyward::ORM::Tables::Column.new(name:, type: :array, nullable:, symbols: item.symbols, element: :enum)
    when Skyward::Core::Types::Refined then ["is #{written}, which isn't a column type yet. #{ELEMENT_TYPES}", nil]
    else ["is #{written}, which isn't a column type. #{ELEMENT_TYPES}", nil]
    end
  end
end
