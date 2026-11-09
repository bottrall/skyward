# frozen_string_literal: true

require "open3"
require "test_helper"
require "tmpdir"

describe "skyward/generator/commands.rb" do
  def skyward(*args, chdir:)
    output, status = Open3.capture2e(Gem.ruby, Gem.bin_path("skyward-core", "skyward"), *args, chdir:)
    [output, status.exitstatus]
  end

  describe "new" do
    it "writes the app in the directory it's run in" do
      Dir.mktmpdir do |directory|
        _output, status = skyward("new", "todos", "--skip-bundle", chdir: directory)

        assert_equal [0, true], [status, File.file?(File.join(directory, "todos", "app.rb"))]
      end
    end

    it "fails saying what it takes when given no name" do
      Dir.mktmpdir do |directory|
        output, status = skyward("new", chdir: directory)

        assert_equal 1, status
        assert_includes output, "skyward: new takes one NAME"
      end
    end
  end
end
