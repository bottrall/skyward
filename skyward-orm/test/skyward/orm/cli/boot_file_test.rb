# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::ORM::CLI::BootFile do
  signatures = File.expand_path("../../../fixtures/tables/sig", __dir__)

  def app(boot_rb)
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(File.join(directory, "boot.rb"), boot_rb) if boot_rb
      yield directory
    ensure
      $LOADED_FEATURES.delete(File.join(directory, "boot.rb"))
    end
  end

  describe ".load" do
    it "says where to run skyward when there's no boot.rb, regenerating nothing" do
      app(nil) do |directory|
        assert_equal "skyward: no boot.rb in #{directory}. Run skyward where your app's boot.rb loads its table " \
                     "classes and calls Skyward.connect.",
                     Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION, -> { flunk })
      end
    end

    it "returns why sig/generated couldn't be regenerated, without requiring boot.rb" do
      app("raise \"required\"\n") do |directory|
        failure = "rbs-inline couldn't regenerate sig/generated:\nboot.rb: can't read\n"
        loaded = Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION, -> { failure })

        assert_equal failure, loaded
      end
    end

    it "requires boot.rb and returns the database it connects to" do
      app(nil) do |directory|
        empty = TestDatabase.empty
        empty.connect.execute("CREATE TABLE booted (id INTEGER PRIMARY KEY)")
        File.write(
          File.join(directory, "boot.rb"),
          "Skyward.connect(#{empty.url.inspect}, signatures: #{signatures.inspect}, check: false)\n"
        )

        loaded = Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION, -> {})

        assert_equal [:booted], loaded.tables.map(&:name)
      end
    end

    it "raises the session's error when boot.rb doesn't connect" do
      app("# Connects to nothing.\n") do |directory|
        error = assert_raises(Skyward::Core::BootError) do
          Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::Session.new, -> {})
        end

        assert_equal "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots.", error.message
      end
    end
  end

  describe ".boot" do
    let(:kernel) do
      Class.new do
        attr_reader :aborted

        def abort(message) = @aborted = message
      end.new
    end

    let(:empty) { TestDatabase.empty }

    define_method(:connecting) { "Skyward.connect(#{empty.url.inspect}, signatures: #{signatures.inspect})\n" }

    it "fails with what's wrong when there's no boot.rb, without running the command" do
      app(nil) do |directory|
        ran = false
        Skyward::ORM::CLI::BootFile.boot(directory, Skyward::ORM::Connection::SESSION, kernel, -> {}) { ran = true }

        assert_equal [Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION, -> {}), false],
                     [kernel.aborted, ran]
      end
    end

    it "boots the app with the schema check off, and runs the command with its database" do
      app(nil) do |directory|
        noted = "File.write(File.join(__dir__, \"check\"), Skyward::ORM::Connection::SESSION.check?.to_s)\n"
        File.write(File.join(directory, "boot.rb"), connecting + noted)
        session = Skyward::ORM::Connection::SESSION
        booted = nil
        Skyward::ORM::CLI::BootFile.boot(directory, session, kernel, -> {}) { |database| booted = database }

        assert_equal [true, "false", nil],
                     [booted.equal?(session.database), File.read(File.join(directory, "check")), kernel.aborted]
      end
    end

    it "fails with only the message of a boot error from booting" do
      app("raise Skyward::Core::BootError, \"Skyward ORM can't connect to a URL with no scheme.\"\n") do |directory|
        Skyward::ORM::CLI::BootFile.boot(directory, Skyward::ORM::Connection::SESSION, kernel, -> {}) { flunk }

        assert_equal "Skyward ORM can't connect to a URL with no scheme.", kernel.aborted
      end
    end

    it "fails with only the message of a boot error from the command" do
      app(nil) do |directory|
        File.write(File.join(directory, "boot.rb"), connecting)
        Skyward::ORM::CLI::BootFile.boot(directory, Skyward::ORM::Connection::SESSION, kernel, -> {}) do
          raise Skyward::Core::BootError, "Todo has no column notes."
        end

        assert_equal "Todo has no column notes.", kernel.aborted
      end
    end
  end
end
