# frozen_string_literal: true

source "https://rubygems.org"

# The dev bundle holds every gem, for linting and type checking. Each gem's
# tests run in that gem's own bundle instead.
gem "skyward", path: "skyward"
gem "skyward-api", path: "skyward-api"
gem "skyward-core", path: "skyward-core"
gem "skyward-orm", path: "skyward-orm"

group :development, :test do
  gem "minitest", "~> 6.0"
  gem "rake", "~> 13.4"

  gem "rubocop", "~> 1.92", require: false
  gem "rubocop-minitest", "~> 0.41", require: false
  gem "rubocop-performance", "~> 1.27", require: false
  gem "rubocop-rake", "~> 0.7", require: false

  # Steep takes the SQLite adapter's driver signatures from the collection,
  # which skips a gem marked `require: false`.
  gem "sqlite3", "~> 2.10"

  gem "rbs", "~> 4.2", require: false
  gem "rbs-inline", "~> 0.14", require: false
  gem "steep", "~> 2.1", require: false

  gem "guard", "~> 2.20", require: false
  gem "guard-shell", "~> 0.7", require: false
end
