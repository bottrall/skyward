# frozen_string_literal: true

require "test_helper"
require "sqlite3"
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
    it "says where to run skyward when there's no boot.rb" do
      app(nil) do |directory|
        assert_equal "skyward: no boot.rb in #{directory}. Run skyward where your app's boot.rb loads its table " \
                     "classes and calls Skyward.connect.",
                     Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION)
      end
    end

    it "requires boot.rb and returns the database it connects to" do
      app(nil) do |directory|
        database = File.join(directory, "app.sqlite3")
        Skyward::ORM::Adapters::SQLite.connect(database).execute("CREATE TABLE booted (id INTEGER PRIMARY KEY)")
        File.write(
          File.join(directory, "boot.rb"),
          "Skyward.connect(#{"sqlite://#{database}".inspect}, signatures: #{signatures.inspect})\n"
        )

        loaded = Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::SESSION)

        assert_equal [:booted], loaded.tables.map(&:name)
      end
    end

    it "raises the session's error when boot.rb doesn't connect" do
      app("# Connects to nothing.\n") do |directory|
        error = assert_raises(Skyward::Core::BootError) do
          Skyward::ORM::CLI::BootFile.load(directory, Skyward::ORM::Connection::Session.new)
        end

        assert_equal "Skyward ORM isn't connected. Call Skyward.connect(url) where your app boots.", error.message
      end
    end
  end
end
