# frozen_string_literal: true

# rbs_inline: enabled

require "skyward/api"
require "skyward/orm"
require "zeitwerk"

loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/lib")
loader.push_dir("#{__dir__}/modules")
loader.inflector.inflect("api" => "API", "health_api" => "HealthAPI")
# skyward serve unloads the app's code to reload it, which Zeitwerk allows only
# for a loader set up with reloading on.
loader.enable_reloading if ENV["RACK_ENV"] == "development"
loader.setup
loader.eager_load

Skyward.connect(ENV.fetch("DATABASE_URL", "postgres://localhost/todos"))
