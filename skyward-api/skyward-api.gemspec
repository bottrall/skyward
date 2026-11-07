# frozen_string_literal: true

require_relative "lib/skyward/api/version"

Gem::Specification.new do |spec|
  spec.name = "skyward-api"
  spec.version = Skyward::API::VERSION
  spec.authors = ["Jake Bottrall"]
  spec.email = ["jakebottrall@gmail.com"]

  spec.summary = "A small, fast web framework where an endpoint is a method, typed with RBS."
  spec.homepage = "https://github.com/bottrall/skyward"
  spec.license = "MIT"
  # Every Ruby that isn't end-of-life.
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/skyward-api"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.{rb,ru}", "sig/**/*.rbs", "README.md"]
  spec.require_paths = ["lib"]

  # The Skyward gems release in lockstep, so each pins the others exactly.
  spec.add_dependency "skyward-core", "= #{Skyward::API::VERSION}"
  spec.add_dependency "zeitwerk", "~> 2.8"
end
