# frozen_string_literal: true

require "skyward/generator"

Skyward::Core::CLI.register(
  "new",
  "Write a new app in NAME/ and install its gems, unless given --skip-bundle"
) do |args|
  Skyward::Generator::CLI::New.run(args, directory: Dir.pwd, out: $stdout, kernel: Kernel)
end
