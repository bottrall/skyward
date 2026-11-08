# frozen_string_literal: true

module Skyward::API::Serve
  extend self

  RACKUP = "#{__dir__}/serve.ru".freeze #: String

  CONFIG = "config.ru" #: String

  # Neither watched nor reloaded, and nor is any hidden directory: the app's
  # gems can be installed under vendor/ or .bundle/.
  IGNORED = %w[tmp log vendor node_modules].freeze #: Array[String]

  WATCHED = "{*.rb,*.rbs,#{CONFIG}}".freeze #: String

  # @rbs directory: String
  # @rbs env: Hash[String, String]
  # @rbs falcon: String?
  # @rbs kernel: singleton(Kernel)
  # @rbs return: void
  def run(directory, env:, falcon:, kernel:)
    unless File.file?(File.join(directory, CONFIG))
      return kernel.abort("skyward: no config.ru in #{directory}. Run skyward serve where your app's config.ru is.")
    end

    unless falcon
      return kernel.abort(
        "skyward: Falcon isn't installed. Add `gem \"falcon\"` to the Gemfile and run `bundle install`, " \
        "or run config.ru under any Rack server, such as Puma."
      )
    end

    kernel.exec(
      { "RACK_ENV" => env.fetch("RACK_ENV", "development") },
      Gem.ruby,
      falcon,
      "serve",
      "--bind",
      "http://localhost:#{env.fetch("PORT", "9292")}",
      "--count",
      "1",
      "--config",
      RACKUP,
      chdir: directory
    )
  end

  # @rbs directory: String
  # @rbs build: ^(String config) -> Skyward::API::_RackApp
  # @rbs clock: ^() -> Float
  # @rbs apis: ^() -> Array[singleton(Skyward::API)]
  # @rbs features: Array[String]
  # @rbs loaders: ^() -> Array[Zeitwerk::Loader]
  # @rbs return: Reloader
  def reloader(directory, build:, clock:, apis:, features:, loaders:)
    Reloader.new(
      watch: -> { watch(directory) },
      load: lambda do
        unload(directory, apis: apis.call, features:, loaders: loaders.call)
        build.call(File.join(directory, CONFIG))
      end,
      clock:
    )
  end

  # @rbs directory: String
  # @rbs return: Hash[String, Time]
  def watch(directory)
    roots = Dir.glob("*/", base: directory).map { |root| root.delete_suffix("/") }.reject { |root| ignored?(root) }
    files = Dir.glob([WATCHED, *roots.map { |root| "#{root}/**/#{WATCHED}" }], base: directory)
    files.to_h { |file| [file, File.mtime(File.join(directory, file))] }
  end

  # @rbs directory: String
  # @rbs apis: Array[singleton(Skyward::API)]
  # @rbs features: Array[String]
  # @rbs loaders: Array[Zeitwerk::Loader]
  # @rbs return: void
  def unload(directory, apis:, features:, loaders:)
    app_loaders, other_loaders = loaders.partition do |loader|
      dirs = loader.dirs
      dirs.any? && dirs.all? { |dir| reloaded?(directory, dir) }
    end
    # Zeitwerk tracks what to unload only with reloading enabled, and it can't
    # be enabled after setup, so the loader's classes could never be reloaded.
    stuck = app_loaders.find { |loader| !loader.reloading_enabled? }
    if stuck
      raise Skyward::BootError,
            "skyward serve can't reload the Zeitwerk loader for #{stuck.dirs.join(", ")}. Call " \
            "`loader.enable_reloading` before `loader.setup` in development, then restart skyward serve."
    end

    apis.select { |api| reloaded_api?(directory, api) }.each(&:clear_declarations)
    features.reject! { |feature| reloaded?(directory, feature) }
    # config.ru sets the app's loaders up again, and Zeitwerk refuses a second
    # loader for a directory one still manages, so each is dropped for good.
    # unregister is experimental, but it's what unload is documented to go with.
    app_loaders.each do |loader|
      # Finishes a setup that failed, so unload removes every autoload it
      # defined, or raises what's still wrong. A set-up loader ignores it.
      loader.setup
      loader.unload
      loader.unregister
    end
    other_loaders.each { |loader| loader.reload if loader.reloading_enabled? }
  end

  private

  # @rbs directory: String
  # @rbs api: singleton(Skyward::API)
  # @rbs return: bool
  def reloaded_api?(directory, api)
    name = api.name
    # const_source_location refuses the name of a class under an anonymous module.
    return false if name.nil? || name.start_with?("#")
    # A class left over from an earlier load keeps its name after its namespace
    # is gone, and const_source_location raises for a missing namespace.
    return false unless Object.const_defined?(name)

    file, = Object.const_source_location(name)
    file ? reloaded?(directory, file) : false
  end

  # @rbs directory: String
  # @rbs path: String
  # @rbs return: bool
  def reloaded?(directory, path)
    return false unless path == directory || path.start_with?("#{directory}/")

    !ignored?(path.delete_prefix(directory).delete_prefix("/").partition("/").first)
  end

  # @rbs root: String
  # @rbs return: bool
  def ignored?(root) = root.start_with?(".") || IGNORED.include?(root)
end
