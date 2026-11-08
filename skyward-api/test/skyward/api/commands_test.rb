# frozen_string_literal: true

require "json"
require "test_helper"
require "open3"
require "tmpdir"

describe "skyward/api/commands.rb" do
  let(:fixture) { File.expand_path("../../fixtures/commands", __dir__) }

  def skyward(*args, chdir:)
    output, status = Open3.capture2e(Gem.ruby, Gem.bin_path("skyward-core", "skyward"), *args, chdir:)
    [output, status.exitstatus]
  end

  describe "serve" do
    it "serves the directory it's run in" do
      Dir.mktmpdir do |directory|
        output, status = skyward("serve", chdir: directory)

        assert_equal 1, status
        assert_includes output, "no config.ru in #{File.realpath(directory)}."
      end
    end

    it "looks for Falcon in the bundle it runs in, which here has none" do
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "config.ru"), "run ->(_env) { [200, {}, []] }\n")
        output, status = skyward("serve", chdir: directory)

        assert_equal 1, status
        assert_includes output, "Falcon isn't installed."
      end
    end
  end

  describe "check" do
    let(:fixtures) { File.expand_path("../../fixtures/check", __dir__) }

    def check(app)
      output, status = skyward("check", chdir: File.join(fixtures, app))
      [output, status, output.lines.grep(/\A(Signatures|Strict boot|Steep): /)]
    end

    it "passes an app with current signatures that boots in strict mode and that Steep passes" do
      _output, status, reports = check("passing")

      assert_equal [0, ["Signatures: passed\n", "Strict boot: passed\n", "Steep: passed\n"]], [status, reports]
    end

    it "runs every check on an app that fails each, saying why, and exits 1" do
      output, status, reports = check("failing")
      reasons = [
        "sig/generated/goodbye.rbs isn't generated from any file",
        "Hello#greet (GET /)\n  Its signature leaves the return type untyped, but strict: true refuses",
        "Ruby::MethodBodyTypeMismatch"
      ]

      assert_equal [1, ["Signatures: failed\n", "Strict boot: failed\n", "Steep: failed\n"], reasons],
                   [status, reports, reasons.select { |reason| output.include?(reason) }]
    end
  end

  describe "routes" do
    it "prints the routes of the app.rb in the directory it's run in, laid out as the README shows" do
      readme = File.read(File.expand_path("../../../README.md", __dir__))
      example = readme[/^\$ skyward routes\n(.*?)^```/m, 1]

      assert_equal [example, 0], skyward("routes", chdir: fixture)
    end

    it "fails without a backtrace in a directory with no app.rb" do
      Dir.mktmpdir do |directory|
        message = Skyward::API::AppFile.load(File.realpath(directory))

        assert_equal ["#{message}\n", 1], skyward("routes", chdir: directory)
      end
    end
  end

  describe "openapi" do
    it "writes the app.rb app's document as pretty JSON with a trailing newline" do
      written, status = skyward("openapi", chdir: fixture)
      document = JSON.parse(written)

      assert_equal [0, "#{JSON.pretty_generate(document)}\n", ["/todos", "/todos/{id}", "/todos/{id}/complete"]],
                   [status, written, document["paths"].keys]
    end
  end
end
