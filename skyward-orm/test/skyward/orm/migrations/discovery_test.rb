# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Migrations::Discovery do
  describe ".table_classes" do
    # The loader is set up in the test, so no other test can have loaded its classes first.
    it "eager-loads, so it finds a table class nothing has loaded" do
      loader = Zeitwerk::Loader.new
      loader.push_dir(File.expand_path("../../../fixtures/discovery", __dir__))
      loader.setup
      unloaded = Object.autoload?(:DiscoveryFixtures)

      found = Skyward::ORM::Migrations::Discovery.table_classes(Zeitwerk::Loader)

      assert_equal [true, ["DiscoveryFixtures::Note"]],
                   [unloaded.to_s.end_with?("discovery_fixtures"), found.map(&:to_s).grep(/\ADiscoveryFixtures::/)]
    ensure
      loader.unload
      loader.unregister
    end
  end
end
