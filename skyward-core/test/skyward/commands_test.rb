# frozen_string_literal: true

require "test_helper"
require "stringio"

describe Skyward::Commands do
  describe ".register" do
    it "adds a command to the default registry" do
      Skyward::Commands.register("commands-test", "Registered by the test") { |_args| nil }

      assert_equal "Registered by the test", Skyward::Commands::REGISTRY.find("commands-test")&.description
    end
  end

  describe ".first_per_gem" do
    it "keeps only the first commands.rb in each gem's directory" do
      paths = %w[
        /app/lib/skyward/orm/commands.rb
        /gems/skyward-api-0.1.0/lib/skyward/api/commands.rb
        /gems/skyward-orm-0.1.0/lib/skyward/orm/commands.rb
      ]

      assert_equal paths.take(2), Skyward::Commands.first_per_gem(paths)
    end
  end

  describe ".run" do
    let(:calls) { [] }
    let(:registry) do
      Skyward::Commands::Registry.new.tap do |registry|
        registry.register("migrate", "Run the pending migrations") { |_args| nil }
        registry.register("routes", "List every route") { |args| calls << args }
      end
    end
    let(:help) do
      "Usage: skyward COMMAND [ARGS]\n  migrate  Run the pending migrations\n  routes   List every route\n"
    end

    def run_with(argv, registry: self.registry)
      out = StringIO.new
      status = Skyward::Commands.run(argv, registry:, out:)
      [out.string, status]
    end

    it "prints the usage and every command, aligned, given no command" do
      assert_equal [help, 0], run_with([])
    end

    it "prints the same for help, --help and -h" do
      results = %w[help --help -h].map { |flag| run_with([flag]) }

      assert_equal [[help, 0]] * 3, results
    end

    it "runs the named command with the remaining arguments and returns 0" do
      status = run_with(%w[routes --verbose api]).last

      assert_equal [[%w[--verbose api]], 0], [calls, status]
    end

    it "prints that no command has the name, then the list, and returns 1" do
      assert_equal ["skyward: no command named nope\n#{help}", 1], run_with(%w[nope])
    end

    it "prints only the usage when no command is registered" do
      assert_equal ["Usage: skyward COMMAND [ARGS]\n", 0], run_with([], registry: Skyward::Commands::Registry.new)
    end
  end
end
