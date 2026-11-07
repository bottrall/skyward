# frozen_string_literal: true

module Skyward::API::Serve
  extend self

  # @rbs directory: String
  # @rbs env: Hash[String, String]
  # @rbs falcon: String?
  # @rbs kernel: singleton(Kernel)
  # @rbs return: void
  def run(directory, env:, falcon:, kernel:)
    config = File.join(directory, "config.ru")
    unless File.file?(config)
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
      config
    )
  end

  # Under Bundler, Gem.find_files and Gem.bin_path see only the bundle's gems,
  # so a gem installed outside the app's bundle isn't found. Checking first
  # spares rescuing the error bin_path raises for a missing gem.
  # @rbs name: String
  # @rbs return: String?
  def executable(name)
    Gem.bin_path(name, name) unless Gem.find_files("#{name}.rb").empty?
  end
end
