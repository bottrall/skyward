# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

describe Skyward::API::CLI::Check do
  let(:calls) { [] }

  def outcome(passed, detail = "") = Skyward::API::CLI::Check::Outcome.new(passed:, detail:)

  def write(directory, file, source)
    path = File.join(directory, file)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def app(files = {})
    Dir.mktmpdir do |directory|
      files.each { |file, source| write(directory, file, source) }
      yield directory
    end
  end

  def capture(answers = {}, generates: {})
    lambda do |env, command, chdir|
      calls << [env, command, chdir]
      output = command.find { |arg| arg.start_with?("--output=") }&.delete_prefix("--output=")
      generates.each { |file, source| write(output, file, source) }
      answers.fetch(command[1], ["", true])
    end
  end

  describe ".run" do
    let(:out) { StringIO.new }

    def run_check(directory, rbs_inline: "/gems/rbs-inline", steep: "/gems/steep", answers: {})
      Skyward::API::CLI::Check.run(directory, out:, capture: capture(answers), rbs_inline:, steep:)
    end

    it "reports each check in turn, and returns 0 when every one passes" do
      app("app.rb" => "", "sig/generated/.keep" => "", "Steepfile" => "") do |directory|
        status = run_check(directory, answers: { "/gems/steep" => ["No type error detected.\n", true] })

        assert_equal [0, "Signatures: passed\nStrict boot: passed\nSteep: passed\nNo type error detected.\n"],
                     [status, out.string]
      end
    end

    it "runs every check after one fails, and returns 1" do
      app("app.rb" => "", "Steepfile" => "") do |directory|
        status = run_check(directory, rbs_inline: nil)
        expected = "Signatures: failed\n#{Skyward::API::CLI::Check::INSTALL_RBS_INLINE}" \
                   "Strict boot: passed\nSteep: passed\n"

        assert_equal [1, expected], [status, out.string]
      end
    end
  end

  describe ".signatures" do
    def signatures(directory, rbs_inline: "/gems/rbs-inline", answers: {}, generates: {})
      Skyward::API::CLI::Check.signatures(directory, capture: capture(answers, generates:), rbs_inline:)
    end

    it "fails saying how to install rbs-inline when the bundle doesn't have it" do
      app do |directory|
        assert_equal outcome(false, Skyward::API::CLI::Check::INSTALL_RBS_INLINE),
                     signatures(directory, rbs_inline: nil)
      end
    end

    it "fails without a sig/generated, saying how to generate it" do
      app("app.rb" => "", "lib/todo.rb" => "") do |directory|
        detail = "There's no sig/generated. Run `bundle exec rbs-inline --output=sig/generated app.rb lib` " \
                 "and commit the result.\n"

        assert_equal outcome(false, detail), signatures(directory)
      end
    end

    it "runs rbs-inline, opt-in, in the directory, on each .rb outside test/, spec/, vendor/ and tmp/" do
      files = %w[
        app.rb config.ru lib/todos/todo.rb app/models/todo.rb public/index.html .bundle/a.rb
        test/a_test.rb spec/a_spec.rb vendor/bundle/a.rb tmp/a.rb sig/generated/app.rbs
      ]
      app(files.to_h { |file| [file, ""] }) do |directory|
        signatures(directory)
        # The --output= path is a random tmpdir.
        run = calls.map do |env, command, chdir|
          [env, command.map { |arg| arg.start_with?("--output=") ? "--output=" : arg }, chdir]
        end

        assert_equal [[{}, [Gem.ruby, "/gems/rbs-inline", "--output=", "app", "app.rb", "lib"], directory]], run
      end
    end

    it "fails with rbs-inline's output when it fails" do
      app("app.rb" => "", "sig/generated/app.rbs" => "") do |directory|
        failure = signatures(directory, answers: { "/gems/rbs-inline" => ["app.rb: syntax error\n", false] })

        assert_equal outcome(false, "app.rb: syntax error\n"), failure
      end
    end

    it "passes when sig/generated is what rbs-inline generates" do
      current = { "app.rbs" => "class Hello\nend\n", "models/todo.rbs" => "class Todo\nend\n" }

      app(current.transform_keys { |file| "sig/generated/#{file}" }) do |directory|
        assert_equal outcome(true), signatures(directory, generates: current)
      end
    end

    it "fails listing each file that's missing, out of date or not generated, and how to regenerate them" do
      app("app.rb" => "", "sig/generated/a.rbs" => "old", "sig/generated/c.rbs" => "") do |directory|
        detail = <<~TEXT
          sig/generated doesn't match what rbs-inline generates from the app's Ruby:
            sig/generated/a.rbs is out of date
            sig/generated/b.rbs is missing
            sig/generated/c.rbs isn't generated from any file
          Run `rm -rf sig/generated && bundle exec rbs-inline --output=sig/generated app.rb` and commit the result.
        TEXT

        assert_equal outcome(false, detail), signatures(directory, generates: { "a.rbs" => "new", "b.rbs" => "" })
      end
    end
  end

  describe ".strict_boot" do
    def strict_boot(directory, answer = ["", true])
      Skyward::API::CLI::Check.strict_boot(directory, capture: capture({ "-e" => answer }))
    end

    it "boots app.rb in a Ruby of its own, in the directory, with SKYWARD_STRICT=1" do
      app do |directory|
        strict_boot(directory)
        command = [Gem.ruby, "-e", Skyward::API::CLI::Check::BOOT]

        assert_equal [[{ "SKYWARD_STRICT" => "1" }, command, directory]], calls
      end
    end

    it "passes or fails as the boot does, with its output" do
      app do |directory|
        booted = [["warning: something\n", true], ["Skyward::Core::BootError: Hello#greet\n", false]].map do |answer|
          strict_boot(directory, answer)
        end

        assert_equal [outcome(true, "warning: something\n"), outcome(false, "Skyward::Core::BootError: Hello#greet\n")],
                     booted
      end
    end
  end

  describe ".type_check" do
    def type_check(directory, steep: "/gems/steep", answer: ["", true])
      Skyward::API::CLI::Check.type_check(directory, capture: capture({ "/gems/steep" => answer }), steep:)
    end

    it "fails saying how to install Steep when the bundle doesn't have it" do
      app("Steepfile" => "") do |directory|
        assert_equal outcome(false, Skyward::API::CLI::Check::INSTALL_STEEP), type_check(directory, steep: nil)
      end
    end

    it "fails without a Steepfile, saying what to add" do
      app do |directory|
        detail = "There's no Steepfile in #{directory}. Add one that checks the app's Ruby: " \
                 "`bundle exec steep init` writes one to start from.\n"

        assert_equal outcome(false, detail), type_check(directory)
      end
    end

    it "runs steep check in the directory, without a daemon" do
      app("Steepfile" => "") do |directory|
        type_check(directory)

        assert_equal [[{}, [Gem.ruby, "/gems/steep", "check", "--no-daemon"], directory]], calls
      end
    end

    it "passes or fails as Steep does, with its output" do
      app("Steepfile" => "") do |directory|
        checked = [["No type error detected.\n", true], ["Detected 1 problem\n", false]].map do |answer|
          type_check(directory, answer:)
        end

        assert_equal [outcome(true, "No type error detected.\n"), outcome(false, "Detected 1 problem\n")], checked
      end
    end
  end
end
