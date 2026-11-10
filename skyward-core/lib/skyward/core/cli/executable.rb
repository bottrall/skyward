# frozen_string_literal: true

module Skyward::Core::CLI::Executable
  extend self

  # @rbs! type capture = ^(Hash[String, String] env, Array[String] command, String chdir) -> [String, bool]

  CAPTURE = lambda do |env, command, chdir|
    # RBS doesn't list the [:child, :out] spelling of this redirect.
    output = IO.popen(env, command, chdir:, err: [:child, 1], &:read)
    # RBS doesn't declare Process.last_status, set by the popen above.
    [output, Process.last_status.success?] # steep:ignore NoMethod
  end #: capture

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
