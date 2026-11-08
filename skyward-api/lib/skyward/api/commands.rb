# frozen_string_literal: true

require "json"
require "skyward/api"

Skyward::Core::CLI.register("serve", "Serve config.ru with Falcon in development, on PORT (default 9292)") do |_args|
  Skyward::API::CLI::Serve.run(
    Dir.pwd,
    env: ENV.to_h,
    falcon: Skyward::API::CLI::Executable.find("falcon"),
    kernel: Kernel
  )
end

Skyward::Core::CLI.register("check", "Check signatures, boot app.rb in strict mode and run Steep") do |_args|
  # So CI shows each check as it finishes, not all of them at exit.
  $stdout.sync = true
  exit Skyward::API::CLI::Check.run(
    Dir.pwd,
    out: $stdout,
    capture: lambda do |env, command, chdir|
      # RBS doesn't list the [:child, :out] spelling of this redirect.
      output = IO.popen(env, command, chdir:, err: [:child, 1], &:read)
      # RBS doesn't declare Process.last_status, set by the popen above.
      [output, Process.last_status.success?] # steep:ignore NoMethod
    end,
    rbs_inline: Skyward::API::CLI::Executable.find("rbs-inline", feature: "rbs/inline"),
    steep: Skyward::API::CLI::Executable.find("steep")
  )
end

Skyward::Core::CLI.register("routes", "Print every route with its handler and signature") do |_args|
  Skyward::API::CLI::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel) { |app| Skyward::API::CLI::Routes.table(app.endpoints) }
end

Skyward::Core::CLI.register("openapi", "Write the OpenAPI document to stdout") do |_args|
  Skyward::API::CLI::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel) { |app| "#{JSON.pretty_generate(app.openapi)}\n" }
end
