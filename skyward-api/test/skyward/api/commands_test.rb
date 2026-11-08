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
