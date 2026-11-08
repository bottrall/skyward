# frozen_string_literal: true

module Skyward::API::Executable
  extend self

  # Under Bundler, Gem.find_files and Gem.bin_path see only the bundle's gems,
  # so a gem installed outside the app's bundle isn't found. Checking first
  # spares rescuing the error bin_path raises for a missing gem.
  # @rbs name: String
  # @rbs feature: String
  # @rbs return: String?
  def find(name, feature: name)
    Gem.bin_path(name, name) unless Gem.find_files("#{feature}.rb").empty?
  end
end
