# frozen_string_literal: true

require "skyward/generator"

Skyward::Core::CLI.register(
  "new",
  "Write a new app in NAME/ and install its gems, unless given --skip-bundle"
) do |args|
  # Under bundle exec, the app's bundle install would otherwise read the
  # Gemfile skyward runs under, not the app's.
  # RBS doesn't declare Bundler.unbundled_env.
  env = defined?(Bundler) ? Bundler.unbundled_env : ENV.to_h # steep:ignore NoMethod
  Skyward::Generator::CLI::New.run(args, directory: Dir.pwd, env:, out: $stdout, kernel: Kernel)
end
