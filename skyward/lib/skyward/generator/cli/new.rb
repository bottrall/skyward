# frozen_string_literal: true

require "fileutils"

module Skyward::Generator::CLI::New
  extend self

  SKIP_BUNDLE = "--skip-bundle" #: String

  # Lowercase, so it names one directory on every filesystem, and a constant
  # once camelized.
  NAME = /\A[a-z][a-z0-9_]*\z/ #: Regexp

  # @rbs (Array[String] args, directory: String, env: Hash[String, String], out: _Writer,
  #       kernel: singleton(Kernel)) -> void
  def run(args, directory:, env:, out:, kernel:)
    names = args - [SKIP_BUNDLE]
    problem = problem(names, directory)
    return kernel.abort(problem) if problem

    name = names.fetch(0)
    app = File.join(directory, name)
    Template.files(name).each do |path, content|
      file = File.join(app, path)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
      File.chmod(0o755, file) if path.start_with?("bin/")
      out.write("Wrote #{File.join(name, path)}\n")
    end
    # system merges env into this process's environment unless told to replace it.
    unless args.include?(SKIP_BUNDLE) || kernel.system(env, "bundle", "install", chdir: app, unsetenv_others: true)
      return kernel.abort("skyward: bundle install failed in #{name}. Fix what it printed, then run bin/setup there.")
    end

    out.write("Next: cd #{name} && bin/setup\n")
  end

  private

  # @rbs names: Array[String]
  # @rbs directory: String
  # @rbs return: String?
  def problem(names, directory)
    name = names.first
    unless name && names.size == 1
      return "skyward: new takes one NAME, the app's directory.\nUsage: skyward new NAME [#{SKIP_BUNDLE}]"
    end
    unless name.match?(NAME)
      return "skyward: #{name} can't name an app. Use lowercase letters, digits and underscores, " \
             "starting with a letter, as in my_app."
    end

    app = File.join(directory, name)
    "skyward: #{name} already exists and isn't an empty directory." if File.exist?(app) && !Dir.empty?(app)
  end
end
