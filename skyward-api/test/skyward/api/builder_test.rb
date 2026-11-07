# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::API::Builder do
  let(:builder) { Skyward::API::Builder.new }
  let(:todos) { Class.new(Skyward::API).new }

  def mount(api, at:)
    Skyward::API::Builder::Mount.new(api:, at:)
  end

  describe "#mount" do
    it "raises a BootError for anything but an API object" do
      api_class = Class.new(Skyward::API)
      error = assert_raises(Skyward::BootError) { builder.mount api_class }

      assert_equal "mount takes a Skyward::API instance, got #{api_class.inspect}", error.message
    end

    it "mounts at / by default" do
      builder.mount todos

      assert_equal [mount(todos, at: "/")], builder.mounts
    end

    it "mounts at the prefix given" do
      builder.mount todos, at: "/todos"

      assert_equal [mount(todos, at: "/todos")], builder.mounts
    end

    it "mounts one object at several prefixes, in order" do
      builder.mount todos, at: "/todos"
      builder.mount todos, at: "/tasks"

      assert_equal [mount(todos, at: "/todos"), mount(todos, at: "/tasks")], builder.mounts
    end

    it "raises a FrozenError once the builder is frozen" do
      builder.freeze

      assert_raises(FrozenError) { builder.mount todos }
    end
  end

  describe "#use" do
    let(:middleware) { Class.new }

    def use(middleware, args, kwargs, block)
      Skyward::API::Builder::Use.new(middleware:, args:, kwargs:, block:)
    end

    it "keeps each middleware with its arguments and block, in order" do
      block = proc { :configured }
      builder.use middleware, "/assets", max_age: 60, &block
      builder.use middleware
      expected = [use(middleware, ["/assets"], { max_age: 60 }, block), use(middleware, [], {}, nil)]

      assert_equal expected, builder.middleware
    end

    it "raises a FrozenError once the builder is frozen" do
      builder.freeze

      assert_raises(FrozenError) { builder.use middleware }
    end
  end

  describe "#static" do
    let(:root) { Dir.mktmpdir }

    before do
      Dir.mkdir(File.join(root, "public"))
      Dir.mkdir(File.join(root, "assets"))
    end

    after { FileUtils.remove_entry(root) }

    def static(prefix, from)
      Skyward::API::Builder::Static.new(prefix:, from:)
    end

    it "resolves from against the current directory" do
      expected = Dir.chdir(root) do
        builder.static "/", from: "public"
        [static("/", File.join(Dir.pwd, "public"))]
      end

      assert_equal expected, builder.statics
    end

    it "raises a BootError when the directory doesn't exist" do
      missing = File.join(root, "missing")
      error = assert_raises(Skyward::BootError) { builder.static "/", from: missing }

      assert_equal %(static "/": no directory at #{missing}), error.message
    end

    it "keeps statics in the order they're declared" do
      builder.static "/", from: File.join(root, "public")
      builder.static "/", from: File.join(root, "assets")

      assert_equal [static("/", File.join(root, "public")), static("/", File.join(root, "assets"))], builder.statics
    end

    it "raises a FrozenError once the builder is frozen" do
      builder.freeze

      assert_raises(FrozenError) { builder.static "/", from: root }
    end
  end
end
