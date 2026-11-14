# frozen_string_literal: true

module Skyward::API::CLI::Check
  extend self

  # @rbs! type capture = Skyward::Core::CLI::Executable::capture

  Outcome = Data.define(
    :passed, #: bool
    :detail #: String
  )

  PASSED = Outcome.new(passed: true, detail: '') #: Outcome

  GENERATED = Skyward::Core::Signatures::Inline::OUTPUT #: String

  STEEPFILE = 'Steepfile' #: String

  # The strict boot's own Ruby runs it, so the forced strict mode, the app's
  # side effects and an exit or crash stay out of skyward check. The require
  # lives here because a `-r` on the command line runs before RUBYOPT's
  # `-rbundler/setup` on newer Rubies, before the bundle's gems are loadable.
  # skyward check writes nothing, so the boot doesn't regenerate sig/generated.
  BOOT = 'require "skyward/api"; ' \
         'Skyward::API::CLI::AppFile.run(Dir.pwd, out: $stdout, kernel: Kernel, generate: -> {}) { "" }' #: String

  INSTALL_RBS_INLINE = "rbs-inline isn't installed. Add `gem \"rbs-inline\", require: false` to the Gemfile " \
                       "and run `bundle install`.\n" #: String

  INSTALL_STEEP = "Steep isn't installed. Add `gem \"steep\", require: false` to the Gemfile " \
                  "and run `bundle install`.\n" #: String

  # @rbs (String directory, out: _Writer, capture: capture, rbs_inline: String?, steep: String?) -> Integer
  def run(directory, out:, capture:, rbs_inline:, steep:)
    checks = {
      'Signatures' => -> { signatures(directory, capture:, rbs_inline:) },
      'Strict boot' => -> { strict_boot(directory, capture:) },
      'Steep' => -> { type_check(directory, capture:, steep:) }
    }
    passed = checks.map do |name, check|
      outcome = check.call
      out.write("#{name}: #{outcome.passed ? 'passed' : 'failed'}\n", outcome.detail)
      outcome.passed
    end
    passed.all? ? 0 : 1
  end

  # @rbs directory: String
  # @rbs capture: capture
  # @rbs rbs_inline: String?
  # @rbs return: Outcome
  def signatures(directory, capture:, rbs_inline:)
    return failed(INSTALL_RBS_INLINE) unless rbs_inline

    inline = Skyward::Core::Signatures::Inline
    paths = inline.sources(directory)
    generate = "bundle exec rbs-inline --output=#{GENERATED} #{paths.join(' ')}"
    generated = File.join(directory, GENERATED)
    unless File.directory?(generated)
      return failed("There's no #{GENERATED}. Run `#{generate}` and commit the result.\n")
    end

    expected = inline.run(directory, rbs_inline:, capture:)
    case expected
    when String then failed(expected)
    else
      stale = differences(inline.rbs_files(generated), expected)
      return PASSED if stale.empty?

      failed(
        [
          "#{GENERATED} doesn't match what rbs-inline generates from the app's Ruby:\n",
          *stale.map { |line| "  #{line}\n" },
          "Run `rm -rf #{GENERATED} && #{generate}` and commit the result.\n"
        ].join
      )
    end
  end

  # @rbs directory: String
  # @rbs capture: capture
  # @rbs return: Outcome
  def strict_boot(directory, capture:)
    output, ok = capture.call({ 'SKYWARD_STRICT' => '1' }, [Gem.ruby, '-e', BOOT], directory)
    Outcome.new(passed: ok, detail: output)
  end

  # @rbs directory: String
  # @rbs capture: capture
  # @rbs steep: String?
  # @rbs return: Outcome
  def type_check(directory, capture:, steep:)
    return failed(INSTALL_STEEP) unless steep
    unless File.file?(File.join(directory, STEEPFILE))
      return failed(
        "There's no #{STEEPFILE} in #{directory}. Add one that checks the app's Ruby: " \
        "`bundle exec steep init` writes one to start from.\n"
      )
    end

    # Steep otherwise checks through any language server it finds running,
    # which can report stale results.
    output, ok = capture.call({}, [Gem.ruby, steep, 'check', '--no-daemon'], directory)
    Outcome.new(passed: ok, detail: output)
  end

  private

  # @rbs detail: String
  # @rbs return: Outcome
  def failed(detail) = Outcome.new(passed: false, detail:)

  # @rbs current: Hash[String, String]
  # @rbs expected: Hash[String, String]
  # @rbs return: Array[String]
  def differences(current, expected)
    (current.keys | expected.keys).sort.filter_map do |file|
      path = "#{GENERATED}/#{file}"
      if !current.key?(file)
        "#{path} is missing"
      elsif !expected.key?(file)
        "#{path} isn't generated from any file"
      elsif current[file] != expected[file]
        "#{path} is out of date"
      end
    end
  end
end
