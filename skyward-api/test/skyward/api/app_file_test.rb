# frozen_string_literal: true

require "stringio"
require "test_helper"
require "tmpdir"

describe Skyward::API::AppFile do
  let(:signatures) { File.expand_path("../../fixtures/boot/sig", __dir__) }
  let(:app) { %(App = Skyward.app(signatures: #{signatures.inspect}, logger: nil) { |_app| nil }\n) }

  after do
    Object.send(:remove_const, :App) if Object.const_defined?(:App)
  end

  def directory(app_rb = app)
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(File.join(directory, "app.rb"), app_rb) if app_rb
      yield directory
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "app.rb"))
    end
  end

  describe ".run" do
    let(:kernel) do
      Class.new do
        attr_reader :aborted

        def abort(message) = @aborted = message
      end.new
    end
    let(:out) { StringIO.new }

    def run_in(directory, &output) = Skyward::API::AppFile.run(directory, out:, kernel:, &output)

    it "fails with what's wrong when app.rb has no App to load" do
      directory(nil) do |path|
        run_in(path) { "unused" }

        assert_equal [Skyward::API::AppFile.load(path), ""], [kernel.aborted, out.string]
      end
    end

    it "writes what it makes of app.rb's App" do
      directory do |path|
        run_in(path) { |loaded| "#{loaded.equal?(App)} #{loaded.endpoints.size}\n" }

        assert_equal ["true 0\n", nil], [out.string, kernel.aborted]
      end
    end

    it "fails with only the message of an app that doesn't boot" do
      directory(%(App = Skyward.app(logger: nil) { |app| app.mount Object.new }\n)) do |path|
        run_in(path) { "unused" }

        assert_match(/\Amount takes a Skyward::API instance, got #<Object:\S+>\z/, kernel.aborted)
        assert_empty out.string
      end
    end

    it "fails with only the message of a boot error from what it makes of the app" do
      directory do |path|
        run_in(path) { raise Skyward::BootError, "Two operations share an ID." }

        assert_equal ["Two operations share an ID.", ""], [kernel.aborted, out.string]
      end
    end
  end

  describe ".load" do
    it "names the directory and what app.rb must assign when it has no app.rb" do
      directory(nil) do |path|
        assert_equal "skyward: no app.rb in #{path}. Run skyward where your app's app.rb assigns " \
                     "App = Skyward.app { ... }.",
                     Skyward::API::AppFile.load(path)
      end
    end

    it "loads app.rb and returns its App" do
      directory do |path|
        loaded = Skyward::API::AppFile.load(path)

        assert_same App, loaded
      end
    end

    it "names the file and what it must assign when it assigns no App" do
      directory("Todos = 1\n") do |path|
        assert_equal "skyward: #{path}/app.rb doesn't assign a Skyward app to App. Assign App = Skyward.app { ... }.",
                     Skyward::API::AppFile.load(path)
      end
    ensure
      Object.send(:remove_const, :Todos) if Object.const_defined?(:Todos)
    end

    it "names the file and what it must assign when its App isn't a Skyward app" do
      directory("App = ->(_env) { [200, {}, []] }\n") do |path|
        assert_equal "skyward: #{path}/app.rb doesn't assign a Skyward app to App. Assign App = Skyward.app { ... }.",
                     Skyward::API::AppFile.load(path)
      end
    end
  end
end
