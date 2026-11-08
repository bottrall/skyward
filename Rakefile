# frozen_string_literal: true

require "bundler"
require "fileutils"
require "open3"
require "rake/testtask"
require "rubocop/rake_task"
require "tmpdir"
require_relative "tooling/lib/release"

# In dependency order, which is the order they're built, installed and
# published in.
GEMS = %w[skyward-core skyward-api skyward-orm skyward].freeze

# Apps built on the gems. Each has its own bundle and signatures, like a gem,
# but is never packaged or released.
EXAMPLES = %w[examples/todos].freeze

BUNDLES = [*GEMS, *EXAMPLES].freeze

PKG = "pkg"

# Rake::TestTask reads TEST as a single glob, so bin/test's comma-separated
# list is taken out of ENV and split by the directory each file is in.
REQUESTED_TESTS = ENV.delete("TEST")&.split(",")

def requested_in(dir)
  return unless REQUESTED_TESTS

  prefix = File.expand_path(dir) + File::SEPARATOR
  REQUESTED_TESTS.map { |file| File.expand_path(file) }
                 .select { |path| path.start_with?(prefix) }
                 .map { |path| path.delete_prefix(prefix) }
end

# A gem's Ruby is under lib/; an example's sits beside its app.rb, where the API README puts an app's.
def ruby_sources(dir) = Dir.glob(%w[lib/**/*.rb *.rb], base: dir)

def write_signatures(dir, output)
  sources = ruby_sources(dir)
  # Starting empty drops a deleted file's signatures.
  FileUtils.rm_rf(File.expand_path(output, dir))
  FileUtils.mkdir_p(File.expand_path(output, dir))
  return if sources.empty?

  sh "rbs-inline", "--opt-out", "--output=#{output}", *sources, chdir: dir, verbose: false
end

# Each gem's tests run in that gem's own bundle, which holds only the gem and
# the Skyward gems it depends on, so a test that reaches for another fails.
# Each example's run in its own bundle the same way.
bundle_test_tasks = BUNDLES.filter_map do |dir|
  files = requested_in(dir)
  next if files == []

  desc "Run #{dir}'s tests in its own bundle"
  task "test:#{dir}" do
    env = { "TEST" => files&.join(",") }.compact
    Bundler.with_unbundled_env { sh env, "bundle", "exec", "rake", "test", chdir: dir }
  end
  "test:#{dir}"
end

tooling_tests = requested_in("tooling") || Dir.glob("test/**/*_test.rb", base: "tooling")
unless tooling_tests.empty?
  Rake::TestTask.new("test:tooling") do |t|
    t.libs = %w[tooling/lib tooling/test]
    t.test_files = tooling_tests.map { |file| File.expand_path(file, "tooling") }
    t.warning = false
  end
end

desc "Run every gem's and example's tests, each in its own bundle, and the tooling's"
task test: [*bundle_test_tasks, *("test:tooling" unless tooling_tests.empty?)]

RuboCop::RakeTask.new do |t|
  # RuboCop also applies AllCops/Exclude from every .rubocop.yml above the
  # project, so a checkout inside another one (a worktree under .claude/)
  # would otherwise inspect nothing and pass.
  t.options = ["--ignore-parent-exclusion", *ENV.fetch("RUBOCOP_OPTS", "").split]
end

desc "Run RuboCop"
task lint: :rubocop

namespace :rbs do
  desc "Fail if rbs_collection.lock.yaml is out of date with rbs_collection.yaml or Gemfile.lock"
  task :collection_check do
    before = File.read("rbs_collection.lock.yaml")
    sh "rbs collection update", verbose: false
    after = File.read("rbs_collection.lock.yaml")
    next if before == after

    File.write("rbs_collection.lock.yaml", before)
    abort "rbs_collection.lock.yaml is out of date; run `bin/setup` and commit the result"
  end

  desc "Install the gem signatures the collection locks"
  task :collection_install do
    sh "rbs collection install"
  end

  desc "Generate RBS signatures from inline annotations in every gem and example"
  task :generate do
    BUNDLES.each { |dir| write_signatures(dir, "sig/generated") }
  end

  desc "Fail if any gem's or example's rbs-inline output is out of date with its Ruby"
  task :check do
    BUNDLES.each do |source|
      Dir.mktmpdir("rbs-check") do |dir|
        write_signatures(source, dir)
        FileUtils.mkdir_p("#{source}/sig/generated")
        sh "diff -ruN #{source}/sig/generated #{dir}" do |ok, _|
          abort "#{source}/sig/generated is out of date; run bin/rbs and commit the result" unless ok
        end
      end
    end
  end

  desc "Watch every gem's Ruby and regenerate RBS files on change"
  task :watch do
    require "guard"
    require "guard/commander"

    Guard.start(no_interactions: true)
  end
end

namespace :steep do
  desc "Type-check every gem with Steep"
  task :check do
    # --no-daemon: Steep 2.1 otherwise routes the check through whatever
    # language server holds the project socket, including orphaned ones,
    # which can hang or report stale results.
    sh "steep check --no-daemon #{ENV.fetch("STEEP_OPTS", "")}".strip
  end
end

desc "Check the RBS signatures and collection are current, then run Steep"
task typecheck: %w[rbs:check rbs:collection_check steep:check]

namespace :package do
  desc "Build every gem into #{PKG}/"
  task :build do
    FileUtils.rm_rf(PKG)
    FileUtils.mkdir_p(PKG)
    GEMS.each do |gem|
      sh "gem", "build", "--quiet", "#{gem}.gemspec", chdir: gem
      FileUtils.mv(Dir["#{gem}/#{gem}-[0-9]*.gem"], PKG)
    end
  end

  desc "Install the built gems into an empty GEM_HOME, load them and run skyward, as a user would"
  task check: :build do
    Dir.mktmpdir("skyward-gems") do |home|
      env = { "GEM_HOME" => home, "GEM_PATH" => home }
      Bundler.with_unbundled_env do
        GEMS.each { |gem| sh env, "gem", "install", "--no-document", *Dir["#{PKG}/#{gem}-[0-9]*.gem"] }
        # Eager loading every loader fails on a file the gemspec left out.
        sh env, Gem.ruby, "-e", <<~RUBY
          require "skyward"
          Zeitwerk::Loader.eager_load_all
          puts "Installed and loaded skyward \#{Skyward::VERSION} from #{PKG}/"
        RUBY
        output, status = Open3.capture2e(env, File.join(home, "bin", "skyward"))
        puts output
        usage = output.start_with?("Usage: skyward COMMAND [ARGS]\n")
        abort "The installed skyward didn't exit 0 and print its usage" unless status.success? && usage
      end
    end
  end
end

desc "Update every lockfile (the dev bundle's, each gem's and each example's) after a version change"
task :lock do
  Bundler.with_unbundled_env { [".", *BUNDLES].each { |dir| sh "bundle", "lock", chdir: dir } }
end

namespace :release do
  desc "Fail unless every gem's version matches TAG (vX.Y.Z), the release being published"
  task :verify, [:tag] do |_task, args|
    tag = args[:tag] || abort("Usage: rake release:verify[vX.Y.Z]")
    shared = Release.shared(Release::VERSION_FILES.map { |file| File.read(file) })
    abort "The gems' versions disagree: #{Release::VERSION_FILES.join(", ")}" unless shared
    abort "#{tag} doesn't match the gems' version, #{shared}" unless tag == "v#{shared}"
  end
end

desc "Run everything CI runs"
task ci: %w[lint typecheck test package:check]

task default: :ci
