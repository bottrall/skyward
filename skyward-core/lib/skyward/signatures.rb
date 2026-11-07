# frozen_string_literal: true

module Skyward::Signatures
  extend self

  # One for the process, so the sig/ each Skyward gem registers when required
  # is in every load the app boots from.
  LOADER = Loader.new #: Loader

  # @rbs path: String
  # @rbs return: void
  def register(path) = LOADER.register(path)

  # @rbs directory: String
  # @rbs return: RBS::DefinitionBuilder
  def load(directory) = LOADER.load(directory)
end
