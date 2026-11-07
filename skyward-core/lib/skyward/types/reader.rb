# frozen_string_literal: true

class Skyward::Types::Reader
  # @rbs @builder: RBS::DefinitionBuilder

  SCALARS = {
    "::Integer" => :integer,
    "::Float" => :float,
    "::String" => :string,
    "::Date" => :date,
    "::Time" => :time
  }.freeze #: Hash[String, Skyward::Types::scalar]

  NIL_LITERAL = Skyward::Types::Literal.new(value: nil) #: Skyward::Types::Literal

  # @rbs builder: RBS::DefinitionBuilder
  # @rbs return: void
  def initialize(builder)
    @builder = builder
  end

  # @rbs type: RBS::Types::t
  # @rbs return: Skyward::Types::result
  def read(type) = read_within(type, [])

  # @rbs klass: Module
  # @rbs return: RBS::TypeName?
  def type_name(klass)
    # An anonymous class has no name, whatever Module#name's signature says.
    return if klass.name.to_s.empty?

    type_name = RBS::TypeName.parse("::#{klass.name}")
    type_name if @builder.env.class_decl?(type_name)
  end

  # @rbs type_name: RBS::TypeName
  # @rbs method_name: Symbol
  # @rbs return: RBS::MethodType?
  def method_type(type_name, method_name)
    @builder.build_instance(type_name).methods[method_name]&.method_types&.first
  rescue RBS::DefinitionError => e
    raise Skyward::BootError, "Can't read the RBS signatures: #{e.message}"
  end

  private

  # @rbs type: RBS::Types::t
  # @rbs path: Array[String]
  # @rbs return: Skyward::Types::result
  def read_within(type, path)
    case type
    when RBS::Types::Bases::Bool then Skyward::Types::Scalar.new(name: :bool)
    when RBS::Types::Bases::Any then Skyward::Types::Scalar.new(name: :untyped)
    when RBS::Types::Bases::Nil then NIL_LITERAL
    when RBS::Types::Literal then literal(type.literal)
    when RBS::Types::Optional
      all_readable([read_within(type.type, path), NIL_LITERAL]) { |members| union(members) }
    when RBS::Types::Union
      all_readable(type.types.map { |member| read_within(member, path) }) { |members| union(members) }
    when RBS::Types::Alias then alias_type(type, path)
    when RBS::Types::Record then record(type, path)
    when RBS::Types::ClassInstance then instance(type, path)
    when RBS::Types::Tuple then unreadable(type, "Array[T], or a record")
    else unreadable(type)
    end
  end

  # @rbs value: RBS::Types::Literal::literal
  # @rbs return: Skyward::Types::t
  def literal(value)
    case value
    when Symbol then Skyward::Types::Enum.new(symbols: [value])
    else Skyward::Types::Literal.new(value:)
    end
  end

  # @rbs types: Array[Skyward::Types::t]
  # @rbs return: Skyward::Types::t
  def union(types)
    members = types.flat_map { |type| flatten(type) }.uniq
    enums = members.filter_map { |member| member.is_a?(Skyward::Types::Enum) ? member : nil }
    if members.size == 1 then members.fetch(0)
    elsif members.include?(NIL_LITERAL) then Skyward::Types::Nullable.new(type: union(members - [NIL_LITERAL]))
    elsif enums.size == members.size then Skyward::Types::Enum.new(symbols: enums.flat_map(&:symbols).uniq)
    else Skyward::Types::Union.new(types: members)
    end
  end

  # @rbs type: Skyward::Types::t
  # @rbs return: Array[Skyward::Types::t]
  def flatten(type)
    case type
    when Skyward::Types::Union then type.types
    when Skyward::Types::Nullable then [type.type, NIL_LITERAL]
    else [type]
    end
  end

  # @rbs type: RBS::Types::Alias
  # @rbs path: Array[String]
  # @rbs return: Skyward::Types::result
  def alias_type(type, path)
    read_within(@builder.expand_alias2(type.name, type.args), enter(written(type), path))
  end

  # @rbs type: RBS::Types::Record
  # @rbs path: Array[String]
  # @rbs return: Skyward::Types::result
  def record(type, path)
    keys = type.all_fields.map { |key, (_, required)| [key.to_s.to_sym, required] } #: Array[[Symbol, bool]]
    results = type.all_fields.values.map { |(field_type, _)| read_within(field_type, path) }
    all_readable(results) { |types| Skyward::Types::Record.new(fields: fields(keys, types)) }
  end

  # @rbs type: RBS::Types::ClassInstance
  # @rbs path: Array[String]
  # @rbs return: Skyward::Types::result
  def instance(type, path)
    name = type.name.to_s
    scalar = SCALARS.fetch(name, nil)
    if scalar then Skyward::Types::Scalar.new(name: scalar)
    elsif name == "::Array" && type.args.size != 1 then unreadable(type, "Array[T]")
    elsif name == "::Array"
      all_readable(type.args.map { |arg| read_within(arg, path) }) do |items|
        Skyward::Types::ArrayOf.new(type: items.fetch(0))
      end
    else named(type, path)
    end
  end

  # @rbs type: RBS::Types::ClassInstance
  # @rbs path: Array[String]
  # @rbs return: Skyward::Types::result
  def named(type, path)
    readers = public_readers(type.name)
    return unreadable(type) if readers.empty?

    name = written(type.name)
    klass = ruby_class(name)
    within = enter(name, path)
    keys = readers.map { |reader| [reader.name, true] } #: Array[[Symbol, bool]]
    results = readers.map { |reader| locate(read_within(reader.type, within), "#{name}##{reader.name}") }
    all_readable(results) { |types| Skyward::Types::Named.new(name:, klass:, fields: fields(keys, types)) }
  end

  # @rbs type_name: RBS::TypeName
  # @rbs return: Array[RBS::AST::Members::AttrReader]
  def public_readers(type_name)
    entry = @builder.env.class_entry(type_name, normalized: true)
    return [] unless entry

    entry.each_decl.flat_map do |decl|
      case decl
      when RBS::AST::Declarations::Class then declared_public_readers(decl)
      else []
      end
    end
  end

  # @rbs decl: RBS::AST::Declarations::Class
  # @rbs return: Array[RBS::AST::Members::AttrReader]
  def declared_public_readers(decl)
    sections = decl.members.slice_before do |member|
      member.is_a?(RBS::AST::Members::Public) || member.is_a?(RBS::AST::Members::Private)
    end
    sections.flat_map do |section|
      default = section.first.is_a?(RBS::AST::Members::Private) ? :private : :public
      section.filter_map do |member|
        next unless member.is_a?(RBS::AST::Members::AttrReader) && member.kind == :instance

        member if (member.visibility || default) == :public
      end
    end
  end

  # @rbs name: String
  # @rbs return: Class
  def ruby_class(name)
    found = Object.const_get(name) if Object.const_defined?(name)
    return found if found.is_a?(Class)

    raise Skyward::BootError, "#{name} has an RBS signature, but no Ruby class is loaded with that name"
  end

  # @rbs name: String
  # @rbs path: Array[String]
  # @rbs return: Array[String]
  def enter(name, path)
    return [*path, name] unless path.include?(name)

    cycle = [*path.drop_while { |entered| entered != name }, name]
    raise Skyward::BootError, "Can't read #{name}: it refers to itself through #{cycle.join(" -> ")}"
  end

  # @rbs keys: Array[[Symbol, bool]]
  # @rbs types: Array[Skyward::Types::t]
  # @rbs return: Array[Skyward::Types::Field]
  def fields(keys, types)
    keys.each_with_index.map do |(name, required), index|
      Skyward::Types::Field.new(name:, type: types.fetch(index), required:)
    end
  end

  # @rbs result: Skyward::Types::result
  # @rbs at: String
  # @rbs return: Skyward::Types::result
  def locate(result, at)
    case result
    when Skyward::Types::Unreadable then result.at ? result : result.with(at:)
    else result
    end
  end

  # @rbs results: Array[Skyward::Types::result]
  # @rbs &: (Array[Skyward::Types::t]) -> Skyward::Types::result
  # @rbs return: Skyward::Types::result
  def all_readable(results)
    results.find { |result| result.is_a?(Skyward::Types::Unreadable) } ||
      yield(results.filter_map { |result| result.is_a?(Skyward::Types::Unreadable) ? nil : result })
  end

  # @rbs type: RBS::Types::t
  # @rbs instead: String
  # @rbs return: Skyward::Types::Unreadable
  def unreadable(type, instead = "a record, or a class with public typed attr_readers")
    Skyward::Types::Unreadable.new(type: written(type), at: nil, instead:)
  end

  # @rbs (_ToS name) -> String
  def written(name) = name.to_s.gsub(/(?<!\w)::/, "")
end
