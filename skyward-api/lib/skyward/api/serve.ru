# frozen_string_literal: true

# skyward serve's composition root. Rack is reached for only here: Skyward API
# doesn't depend on it, and Falcon brings it.
require "skyward/api"

run Skyward::API::Serve.reloader(
  Dir.pwd,
  build: ->(config) { Rack::Builder.parse_file(config) },
  clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
  apis: -> { ObjectSpace.each_object(Skyward::API.singleton_class).to_a },
  features: $LOADED_FEATURES,
  # Zeitwerk has no public list of its loaders, and ObjectSpace would go on
  # finding the ones serve unregisters until they're garbage collected.
  loaders: -> { Zeitwerk::Registry.loaders.enum_for(:each).to_a }
)
