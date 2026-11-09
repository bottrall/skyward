# frozen_string_literal: true

require "minitest/autorun"
require "skyward"

# The database the tests that use one run on. TEST_DATABASE picks it, as it
# does for Skyward ORM's suite: sqlite, the default, in memory, or postgresql,
# at TEST_POSTGRES_URL, emptied first.
module TestDatabase
  extend self

  # Emptying the database reads no table classes, so it loads no signatures of the app's.
  SIGNATURES = File.join(__dir__, "no-signatures")

  # The connections earlier tests left open are closed first, so none holds a
  # lock the drop waits on, or counts against max_connections. Each statement
  # runs on its own, as Skyward.query runs one.
  RESET = [
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity " \
    "WHERE datname = current_database() AND pid <> pg_backend_pid()",
    "DROP SCHEMA IF EXISTS public CASCADE",
    "CREATE SCHEMA public"
  ].freeze

  def url(kind = ENV.fetch("TEST_DATABASE", "sqlite"))
    case kind
    when "sqlite" then "sqlite://:memory:"
    when "postgresql" then reset(postgres_url)
    else raise ArgumentError, "TEST_DATABASE is sqlite or postgresql, not #{kind.inspect}"
    end
  end

  private

  def postgres_url
    ENV.fetch("TEST_POSTGRES_URL") do
      raise "Set TEST_POSTGRES_URL to a PostgreSQL database the tests can empty. CONTRIBUTING.md says how."
    end
  end

  def reset(url)
    Skyward.connect(url, signatures: SIGNATURES, check: false)
    RESET.each { |sql| Skyward.query(sql) }
    url
  end
end
