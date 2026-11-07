# frozen_string_literal: true

require_relative "lib/skyward/core/version"

Gem::Specification.new do |spec|
  spec.name = "skyward-core"
  spec.version = Skyward::Core::VERSION
  spec.authors = ["Jake Bottrall"]
  spec.email = ["jakebottrall@gmail.com"]

  spec.summary = "The plumbing Skyward API and Skyward ORM share: the namespace, the skyward command and RBS loading."
  spec.homepage = "https://github.com/bottrall/skyward"
  spec.license = "MIT"
  # Every Ruby that isn't end-of-life.
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/skyward-core"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["skyward"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rbs", "~> 4.2"
  spec.add_dependency "zeitwerk", "~> 2.8"
end
