# frozen_string_literal: true

require_relative "lib/skyward/version"

Gem::Specification.new do |spec|
  spec.name = "skyward"
  spec.version = Skyward::VERSION
  spec.authors = ["Jake Bottrall"]
  spec.email = ["jakebottrall@gmail.com"]

  spec.summary = "Skyward API and Skyward ORM: typed Ruby apps where an endpoint is a method and a row is a value."
  spec.homepage = "https://github.com/bottrall/skyward"
  spec.license = "MIT"
  # Every Ruby that isn't end-of-life.
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main/skyward"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # The .tt files are the app skyward new writes, and FNM_DOTMATCH keeps its
  # .gitignore and .keep files.
  spec.files = Dir.glob(["lib/**/*.{rb,tt}", "sig/**/*.rbs", "README.md"], File::FNM_DOTMATCH)
  spec.require_paths = ["lib"]

  # The Skyward gems release in lockstep, so each pins the others exactly.
  spec.add_dependency "skyward-api", "= #{Skyward::VERSION}"
  spec.add_dependency "skyward-core", "= #{Skyward::VERSION}"
  spec.add_dependency "skyward-orm", "= #{Skyward::VERSION}"
  spec.add_dependency "zeitwerk", "~> 2.8"
end
