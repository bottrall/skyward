# frozen_string_literal: true

require "test_helper"

describe Skyward::ORM::Adapters do
  adapters = Skyward::ORM::Adapters
  adapter = Data.define(:driver) { def connect(location) = "connection to #{location}" }.new(driver: "fakedb")
  schemes = { "fake" => adapter, "other" => adapter }.freeze
  requirer = ->(_feature) {}

  def refusal(url, schemes, requirer)
    assert_raises(Skyward::Core::BootError) { Skyward::ORM::Adapters.connect(url, schemes:, requirer:) }.message
  end

  describe ".connect" do
    it "picks the adapter by the URL's scheme" do
      picked, = adapters.connect("fake://todos.db", schemes:, requirer:)

      assert_same adapter, picked
    end

    it "refuses a scheme it has no adapter for, naming the ones it has" do
      assert_equal "Skyward ORM can't connect to a mysql:// URL. It connects to fake://, other:// URLs.",
                   refusal("mysql://user:secret@localhost/todos", schemes, requirer)
    end

    it "refuses a URL with no scheme, without showing it" do
      assert_equal "Skyward ORM can't connect to a URL with no scheme. It connects to fake://, other:// URLs.",
                   refusal("user:secret@todos.db", schemes, requirer)
    end

    it "requires the adapter's driver" do
      required = []
      adapters.connect("fake://todos.db", schemes:, requirer: ->(feature) { required << feature })

      assert_equal ["fakedb"], required
    end

    it "says to add the driver to the Gemfile when it isn't installed" do
      missing = ->(feature) { raise LoadError, "cannot load such file -- #{feature}" }

      assert_equal "Skyward ORM needs the fakedb gem to connect to a fake:// URL. " \
                   "Add `gem \"fakedb\"` to your Gemfile.",
                   refusal("fake://todos.db", schemes, missing)
    end

    it "connects to the database the rest of the URL locates" do
      _, connection = adapters.connect("fake://todos.db", schemes:, requirer:)

      assert_equal "connection to todos.db", connection
    end
  end
end
