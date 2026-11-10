# frozen_string_literal: true

module Skyward::Generator::CLI::New::Template
  extend self

  DIRECTORY = "#{__dir__}/template".freeze #: String

  # Every file there ends in it, so none of the tools that read the gem's own
  # Ruby, signatures and Steepfile takes the app's for the gem's.
  SUFFIX = ".tt" #: String

  PLACEHOLDER = /\{\{\w+\}\}/ #: Regexp

  # FNM_DOTMATCH, so the app gets its .gitignore, and the .keep files that make
  # git keep its empty directories.
  FILES = Dir.glob("**/*#{SUFFIX}", File::FNM_DOTMATCH, base: DIRECTORY).to_h do |file|
    [file.delete_suffix(SUFFIX), File.read(File.join(DIRECTORY, file))]
  end.freeze #: Hash[String, String]

  # @rbs name: String
  # @rbs return: Hash[String, String]
  def files(name)
    values = { "{{name}}" => name, "{{title}}" => title(name), "{{version}}" => Skyward::VERSION }
    FILES.transform_values { |content| content.gsub(PLACEHOLDER) { |key| values.fetch(key) } }
  end

  private

  # @rbs name: String
  # @rbs return: String
  def title(name) = name.split("_").map(&:capitalize).join
end
