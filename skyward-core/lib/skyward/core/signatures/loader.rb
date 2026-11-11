# frozen_string_literal: true

require "rbs"

class Skyward::Core::Signatures::Loader
  # @rbs @gems: Array[String]

  # @rbs return: void
  def initialize
    @gems = []
  end

  # @rbs path: String
  # @rbs return: void
  def register(path)
    @gems |= [File.expand_path(path)]
  end

  # @rbs directory: String
  # @rbs return: RBS::DefinitionBuilder
  def load(directory)
    loader = RBS::EnvironmentLoader.new
    [directory, *@gems].each { |path| loader.add(path: Pathname(path)) }
    %w[date time bigdecimal].each { |library| loader.add(library:, version: nil) }
    env = RBS::Environment.from_loader(loader).resolve_type_names
    # RBS otherwise defers this conflict until a definition is built, past boot.
    env.validate_type_params
    RBS::DefinitionBuilder.new(env:)
  rescue RBS::ParsingError => e
    raise Skyward::Core::BootError, failure("Syntax error: #{e.error_message}.", [e.location])
  rescue RBS::DuplicatedDeclarationError => e
    names = e.decls.filter_map { |decl| name_location(decl) }
    raise Skyward::Core::BootError, failure("#{e.name.to_s.delete_prefix("::")} is declared twice.", names)
  rescue RBS::GenericParameterMismatchError => e
    location = e.decl.location
    message = e.message.delete_prefix("#{RBS::Location.to_string(location)}: ")
    raise Skyward::Core::BootError, failure(message, [location&.[](:name)].compact)
  end

  private

  # @rbs decl: RBS::DuplicatedDeclarationError::declaration
  # @rbs return: RBS::Location[untyped, untyped]?
  def name_location(decl)
    case decl
    when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias then decl.location&.[](:new_name)
    else decl.location&.[](:name)
    end
  end

  # @rbs message: String
  # @rbs locations: Array[RBS::Location[untyped, untyped]]
  # @rbs return: String
  def failure(message, locations)
    spots = locations.map { |location| Skyward::Core::Diagnostics::Spots.rbs(location) }
    ["Can't load the RBS signatures: #{message}", Skyward::Core::Diagnostics::Excerpt.render(spots)].compact.join("\n\n")
  end
end
