# frozen_string_literal: true

require "test_helper"

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
end
