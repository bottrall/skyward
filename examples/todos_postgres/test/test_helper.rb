# frozen_string_literal: true

require "minitest/autorun"
require "skyward/orm"
require "stringio"

# A database of the suite's own, unless TEST_DATABASE_URL names another, so the
# tests never run against the DATABASE_URL the app uses.
ENV["DATABASE_URL"] = ENV.fetch("TEST_DATABASE_URL", "postgres://localhost/todos_test")

# App logs every request to the $stdout it boots with, which would bury the
# test report, so it boots with one of its own. Its boot.rb connects with the
# schema check on, which an unmigrated database fails, so the check waits for
# Skyward.migrate.
stdout = $stdout
$stdout = StringIO.new
Skyward::ORM::Connection::SESSION.without_check { require_relative "../app" }
$stdout = stdout
Skyward.migrate(File.expand_path("../db/migrate", __dir__))

# Every test, App's HTTP tests too, runs in a transaction that's rolled back
# after it. The test client calls App on the test's fiber, so its requests run
# in that transaction.
Minitest::Test.include(Skyward::ORM::Transactional)
