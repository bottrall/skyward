# frozen_string_literal: true

require "rbs"

class Skyward::Signatures::Loader
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
    %w[date time].each { |library| loader.add(library:, version: nil) }
    env = RBS::Environment.from_loader(loader).resolve_type_names
    # RBS otherwise defers this conflict until a definition is built, past boot.
    env.validate_type_params
    RBS::DefinitionBuilder.new(env:)
  rescue RBS::DuplicatedDeclarationError => e
    locations = e.decls.map { |decl| RBS::Location.to_string(decl.location) }
    raise Skyward::BootError, "Can't load the RBS signatures: #{e.name} is declared at #{locations.join(" and ")}"
  rescue RBS::ParsingError, RBS::GenericParameterMismatchError => e
    raise Skyward::BootError, "Can't load the RBS signatures: #{e.message}"
  end
end
