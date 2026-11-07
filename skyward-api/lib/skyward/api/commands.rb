# frozen_string_literal: true

require "skyward/api"

Skyward::Commands.register("serve", "Serve config.ru with Falcon in development, on PORT (default 9292)") do |_args|
  Skyward::API::Serve.run(Dir.pwd, env: ENV.to_h, falcon: Skyward::API::Serve.executable("falcon"), kernel: Kernel)
end
