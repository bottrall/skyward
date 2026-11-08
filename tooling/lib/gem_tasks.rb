# frozen_string_literal: true

require "rake/testtask"

# Loaded by each gem's and example's Rakefile, which runs in its own bundle.
# Rake::TestTask reads TEST as a single glob, so the comma-separated list the
# root Rakefile passes is taken out of ENV and split here.
requested = ENV.delete("TEST")&.split(",")

Rake::TestTask.new do |t|
  t.libs = %w[lib test]
  t.test_files = requested || FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: :test
