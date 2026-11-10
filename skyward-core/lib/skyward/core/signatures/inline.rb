# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Skyward::Core::Signatures::Inline
  extend self

  OUTPUT = "sig/generated" #: String

  # None holds the app's contract: its tests, its installed gems and scratch.
  UNCHECKED = %w[test spec vendor tmp].freeze #: Array[String]

  # rbs-inline writes to scratch, so a file it no longer generates can be
  # removed, and only a file whose content changed is written: skyward serve
  # reloads on every .rbs file written.
  # @rbs directory: String
  # @rbs rbs_inline: String?
  # @rbs capture: Skyward::Core::CLI::Executable::capture
  # @rbs return: String?
  def generate(directory, rbs_inline:, capture:)
    return unless rbs_inline

    files = run(directory, rbs_inline:, capture:)
    case files
    when String then "rbs-inline couldn't regenerate #{OUTPUT}:\n#{files}"
    else
      write(File.join(directory, OUTPUT), files)
      nil
    end
  end

  # @rbs directory: String
  # @rbs rbs_inline: String
  # @rbs capture: Skyward::Core::CLI::Executable::capture
  # @rbs return: Hash[String, String] | String
  def run(directory, rbs_inline:, capture:)
    Dir.mktmpdir("skyward-signatures") do |output|
      log, ok = capture.call({}, [Gem.ruby, rbs_inline, "--output=#{output}", *sources(directory)], directory)
      ok ? rbs_files(output) : log
    end
  end

  # @rbs directory: String
  # @rbs return: Array[String]
  def sources(directory)
    roots = Dir.glob("*/", base: directory).map { |root| root.delete_suffix("/") } - UNCHECKED
    files = Dir.glob("*.rb", base: directory)
    [*files, *roots.reject { |root| Dir.glob("#{root}/**/*.rb", base: directory).empty? }].sort
  end

  # @rbs directory: String
  # @rbs return: Hash[String, String]
  def rbs_files(directory)
    Dir.glob("**/*.rbs", base: directory).to_h { |file| [file, File.read(File.join(directory, file))] }
  end

  private

  # @rbs generated: String
  # @rbs files: Hash[String, String]
  # @rbs return: void
  def write(generated, files)
    current = rbs_files(generated)
    files.reject { |file, source| current[file] == source }.each do |file, source|
      path = File.join(generated, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, source)
    end
    (current.keys - files.keys).each { |file| File.delete(File.join(generated, file)) }
    # Deepest first, so a directory emptied of directories goes too.
    Dir.glob("**/*/", base: generated).sort.reverse_each do |dir|
      path = File.join(generated, dir)
      Dir.rmdir(path) if Dir.empty?(path)
    end
  end
end
