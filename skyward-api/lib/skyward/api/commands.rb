# frozen_string_literal: true

require 'json'
require 'skyward/api'

generate = lambda do
  Skyward::Core::Signatures::Inline.generate(
    Dir.pwd,
    rbs_inline: Skyward::Core::CLI::Executable.find('rbs-inline', feature: 'rbs/inline'),
    capture: Skyward::Core::CLI::Executable::CAPTURE
  )
end

Skyward::Core::CLI.register('serve', 'Serve config.ru with Falcon in development, on PORT (default 9292)') do |_args|
  Skyward::API::CLI::Serve.run(
    Dir.pwd,
    env: ENV.to_h,
    falcon: Skyward::Core::CLI::Executable.find('falcon'),
    kernel: Kernel
  )
end

Skyward::Core::CLI.register('check', 'Check signatures, boot app.rb in strict mode and run Steep') do |_args|
  # So CI shows each check as it finishes, not all of them at exit.
  $stdout.sync = true
  exit Skyward::API::CLI::Check.run(
    Dir.pwd,
    out: $stdout,
    capture: Skyward::Core::CLI::Executable::CAPTURE,
    rbs_inline: Skyward::Core::CLI::Executable.find('rbs-inline', feature: 'rbs/inline'),
    steep: Skyward::Core::CLI::Executable.find('steep')
  )
end

Skyward::Core::CLI.register('routes', 'Print every route with its handler and signature') do |_args|
  Skyward::API::CLI::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel, generate:) do |app|
    Skyward::API::CLI::Routes.table(app.endpoints)
  end
end

Skyward::Core::CLI.register('openapi', 'Write the OpenAPI document to stdout') do |_args|
  Skyward::API::CLI::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel, generate:) do |app|
    "#{JSON.pretty_generate(app.openapi)}\n"
  end
end
