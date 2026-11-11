# frozen_string_literal: true

require "open3"
require "test_helper"
require "tmpdir"

describe "skyward/generator/commands.rb" do
  def skyward(*args, chdir:, env: {})
    output, status = Open3.capture2e(env, Gem.ruby, Gem.bin_path("skyward-core", "skyward"), *args, chdir:)
    [output, status.exitstatus]
  end

  describe "new" do
    it "writes the app in the directory it's run in" do
      Dir.mktmpdir do |directory|
        _output, status = skyward("new", "todos", "--skip-bundle", chdir: directory)

        assert_equal [0, true], [status, File.file?(File.join(directory, "todos", "app.rb"))]
      end
    end

    it "installs the gems outside the bundle it's run under" do
      Dir.mktmpdir do |directory|
        bin = File.join(directory, "bin")
        Dir.mkdir(bin)
        File.write(File.join(bin, "bundle"), "#!/bin/sh\necho \"bundle $1 sees BUNDLE_GEMFILE=$BUNDLE_GEMFILE\"\n")
        File.chmod(0o755, File.join(bin, "bundle"))
        path = [bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
        # Bundler restores PATH from BUNDLER_ORIG_PATH, which the bundle exec running the tests set.
        env = {
          "BUNDLE_GEMFILE" => File.expand_path("../../../Gemfile", __dir__),
          "RUBYOPT" => "-rbundler/setup",
          "PATH" => path,
          "BUNDLER_ORIG_PATH" => path
        }
        output, status = skyward("new", "todos", chdir: directory, env:)

        assert_equal 0, status
        assert_includes output, "bundle install sees BUNDLE_GEMFILE=\n"
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
