# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::API::Serve do
  describe ".run" do
    let(:kernel) do
      Class.new do
        attr_reader :calls

        def initialize
          @calls = []
        end

        def abort(message) = @calls << [:abort, message]

        def exec(*args) = @calls << [:exec, *args]
      end.new
    end

    def serve(config_ru: true, env: {}, falcon: "/gems/falcon/bin/falcon")
      Dir.mktmpdir do |directory|
        File.write(File.join(directory, "config.ru"), "run ->(_env) { [200, {}, []] }\n") if config_ru
        Skyward::API::Serve.run(directory, env:, falcon:, kernel:)
        yield directory
      end
    end

    it "fails naming the directory when it has no config.ru" do
      serve(config_ru: false) do |directory|
        message = "skyward: no config.ru in #{directory}. Run skyward serve where your app's config.ru is."

        assert_equal [[:abort, message]], kernel.calls
      end
    end

    it "fails saying how to install Falcon when it can't be loaded" do
      message = "skyward: Falcon isn't installed. Add `gem \"falcon\"` to the Gemfile and run `bundle install`, " \
                "or run config.ru under any Rack server, such as Puma."

      serve(falcon: nil) { assert_equal [[:abort, message]], kernel.calls }
    end

    it "runs one Falcon process for config.ru, on localhost and PORT, in development" do
      serve(env: { "PORT" => "4567" }) do |directory|
        command = [
          :exec,
          { "RACK_ENV" => "development" },
          Gem.ruby,
          "/gems/falcon/bin/falcon",
          "serve",
          "--bind",
          "http://localhost:4567",
          "--count",
          "1",
          "--config",
          File.join(directory, "config.ru")
        ]

        assert_equal [command], kernel.calls
      end
    end

    it "keeps a RACK_ENV that's already set" do
      serve(env: { "RACK_ENV" => "production" }) do
        assert_includes kernel.calls.first, { "RACK_ENV" => "production" }
      end
    end

    it "binds port 9292 when PORT isn't set" do
      serve { assert_includes kernel.calls.first, "http://localhost:9292" }
    end
  end

  describe ".executable" do
    it "finds the executable of a gem in the bundle" do
      assert_equal Gem.bin_path("rake", "rake"), Skyward::API::Serve.executable("rake")
    end

    it "returns nil for a gem the bundle doesn't have" do
      assert_nil Skyward::API::Serve.executable("falcon")
    end
  end
end
