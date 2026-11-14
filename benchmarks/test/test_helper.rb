# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../boot"

# Each orm group's process connects to one database, and its scenarios query
# whichever is current. Here SQLite's is, and a test switches to PostgreSQL's,
# at TEST_POSTGRES_URL, with Skyward.using.
Skyward.connect("sqlite://:memory:", check: false)
Bench::Queries.prepare("sqlite")

POSTGRES = ENV["TEST_POSTGRES_URL"]&.then { |url| Skyward.connect(url, check: false, default: false) }
Skyward.using(POSTGRES) { Bench::Queries.prepare("postgresql") } if POSTGRES
