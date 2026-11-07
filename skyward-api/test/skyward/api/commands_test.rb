# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

describe "skyward/api/commands.rb" do
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
end
