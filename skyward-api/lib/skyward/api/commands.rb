# frozen_string_literal: true

require "json"
require "skyward/api"

Skyward::Commands.register("serve", "Serve config.ru with Falcon in development, on PORT (default 9292)") do |_args|
  Skyward::API::Serve.run(Dir.pwd, env: ENV.to_h, falcon: Skyward::API::Serve.executable("falcon"), kernel: Kernel)
end

Skyward::Commands.register("routes", "Print every route with its handler and signature") do |_args|
  Skyward::API::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel) { |app| Skyward::API::Routes.table(app.endpoints) }
end

Skyward::Commands.register("openapi", "Write the OpenAPI document to stdout") do |_args|
  Skyward::API::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel) { |app| "#{JSON.pretty_generate(app.openapi)}\n" }
end
