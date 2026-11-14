# frozen_string_literal: true

# rbs_inline: enabled

# Runs one group's scenarios in a process of its own, for Bench::Runner:
#
#   ruby group.rb GROUP NAMES [OUTPUT]
#
# NAMES are comma-separated prefixes, and empty selects every scenario.

require_relative "boot"

group = ARGV.fetch(0)
names = ARGV.fetch(1).split(",")
output = ARGV[2]

versions =
  if group == "api"
    {} #: Hash[String, String]
  else
    database = group.delete_prefix("orm.")
    Skyward.connect(database == "sqlite" ? "sqlite://:memory:" : ENV.fetch("TEST_POSTGRES_URL"), check: false)
    Bench::Queries.prepare(database)
    { database => Bench::Queries.version(database) }
  end

selected = Bench::Groups.matching(Bench::Groups.scenarios(group), names)
failures = Bench::Measure.failures(selected)
abort failures.join("\n") unless failures.empty?

File.write(output, JSON.generate({ results: Bench::Measure.results(selected).map(&:to_h), versions: })) if output
