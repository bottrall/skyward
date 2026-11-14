# frozen_string_literal: true

# skyward serve's composition root. Rack is reached for only here: Skyward API
# doesn't depend on it, and Falcon brings it.
require 'skyward/api'

rbs_inline = Skyward::Core::CLI::Executable.find('rbs-inline', feature: 'rbs/inline')

capture = Skyward::Core::CLI::Executable::CAPTURE
generate = rbs_inline && -> { Skyward::Core::Signatures::Inline.generate(Dir.pwd, rbs_inline:, capture:) }

run Skyward::API::CLI::Serve.reloader(
  Dir.pwd,
  build: ->(config) { Rack::Builder.parse_file(config) },
  clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
  apis: -> { ObjectSpace.each_object(Skyward::API.singleton_class).to_a },
  features: $LOADED_FEATURES,
  # Zeitwerk has no public list of its loaders, and ObjectSpace would go on
  # finding the ones serve unregisters until they're garbage collected.
  loaders: -> { Zeitwerk::Registry.loaders.enum_for(:each).to_a },
  generate:,
  # Ruby ends the thread when Falcon's worker exits.
  every: lambda do |interval, &tick|
    Thread.new do
      loop do
        sleep(interval)
        tick.call
      end
    end
  end
)
