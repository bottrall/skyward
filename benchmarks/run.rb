# frozen_string_literal: true

# rbs_inline: enabled

require_relative "boot"
require "tmpdir"

dir = __dir__ #: String
script = File.join(dir, "group.rb")
cpuinfo = "/proc/cpuinfo"
environment = Bench::Environment.describe(
  commit: `git rev-parse HEAD`.strip,
  ruby: RUBY_DESCRIPTION,
  cpuinfo: File.exist?(cpuinfo) ? File.read(cpuinfo) : nil
)

report = Dir.mktmpdir("bench") do |scratch|
  Bench::Runner.call(
    ARGV,
    scenario_names: Bench::Groups::ALL.flat_map { |group| Bench::Groups.scenarios(group).map(&:name) },
    postgres_url: ENV.fetch("TEST_POSTGRES_URL", nil),
    environment:,
    scratch:,
    run: ->(group, names, output) { system(Gem.ruby, script, *[group, names, output].compact) == true },
    say: ->(line) { puts line }
  )
end

case report
when String then abort report
else
  Bench::Results.write(report, File.expand_path("../tmp/bench", dir))
  puts "", Bench::Results.markdown(report)
end
