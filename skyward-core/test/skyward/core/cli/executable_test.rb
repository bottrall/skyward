# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::Core::CLI::Executable do
  describe "CAPTURE" do
    it "runs the command in the directory with the environment, giving its output, errors included, and success" do
      Dir.mktmpdir do |tmp|
        directory = File.realpath(tmp)
        script = '$stdout.write(Dir.pwd, " ", ENV["GREETING"]); $stdout.flush; warn "!"; exit 3'

        assert_equal ["#{directory} hello!\n", false],
                     Skyward::Core::CLI::Executable::CAPTURE.call(
                       { "GREETING" => "hello" },
                       [Gem.ruby, "-e", script],
                       directory
                     )
      end
    end

    it "says when the command succeeded" do
      assert_equal ["", true], Skyward::Core::CLI::Executable::CAPTURE.call({}, [Gem.ruby, "-e", ""], Dir.pwd)
    end
  end

  describe ".find" do
    it "finds the executable of a gem in the bundle" do
      assert_equal Gem.bin_path("rake", "rake"), Skyward::Core::CLI::Executable.find("rake")
    end

    it "finds a gem in the bundle by a file it can be required by" do
      assert_equal Gem.bin_path("rbs", "rbs"), Skyward::Core::CLI::Executable.find("rbs", feature: "rbs/cli")
    end

    it "returns nil for a gem the bundle doesn't have" do
      assert_nil Skyward::Core::CLI::Executable.find("falcon")
    end
  end
end
