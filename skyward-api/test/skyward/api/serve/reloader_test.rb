# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Serve::Reloader do
  let(:fake_world) do
    Class.new do
      attr_accessor :now
      attr_reader :loads, :watches

      def initialize(loads)
        @now = 0.0
        @files = { "app.rb" => Time.at(0) }
        @pending = loads
        @loads = 0
        @watches = 0
      end

      def watch
        @watches += 1
        @files
      end

      def load
        @loads += 1
        case (result = @pending.shift)
        when Exception then raise result
        when Thread::Queue then result.pop
        else result
        end
      end

      def change
        @now += 1
        @files = @files.transform_values { |time| time + 1 }
      end
    end
  end

  let(:env) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/" } }

  def world_with(*loads) = fake_world.new(loads)

  def app(name) = ->(_env) { [200, {}, [name]] }

  def reloader(world)
    Skyward::API::Serve::Reloader.new(watch: world.method(:watch), load: world.method(:load), clock: -> { world.now })
  end

  def body(reloader) = reloader.call(env).last.first

  describe "#call" do
    it "serves the app it loads when it's created" do
      assert_equal "first", body(reloader(world_with(app("first"))))
    end

    it "finishes a request in flight on the app it started with" do
      served = nil
      inner = nil
      world = nil
      outer = lambda do |request|
        world.change
        inner = served.call(request).last.first
        [200, {}, ["first"]]
      end
      world = world_with(outer, app("second"))
      served = reloader(world)

      assert_equal %w[first second], [body(served), inner]
    end

    it "makes a request wait for a reload in progress, then serves the new app" do
      gate = Thread::Queue.new
      world = world_with(app("first"), gate)
      served = reloader(world)
      world.change
      reloading = Thread.new { body(served) }
      Thread.pass while reloading.status == "run"
      waiting = Thread.new { body(served) }
      Thread.pass while waiting.status == "run"
      gate << app("second")

      assert_equal [%w[second second], 2], [[reloading.value, waiting.value], world.loads]
    end

    it "doesn't look at the files again within half a second" do
      world = world_with(app("first"))
      served = reloader(world)
      world.now = 0.4
      body(served)

      assert_equal 1, world.watches
    end

    it "keeps the app when no file changed" do
      world = world_with(app("first"), app("second"))
      served = reloader(world)
      world.now = 0.5

      assert_equal "first", body(served)
    end

    it "serves a new app once a file changed" do
      world = world_with(app("first"), app("second"))
      served = reloader(world)
      world.change

      assert_equal "second", body(served)
    end

    it "answers a failed load with a 500 problem showing the error" do
      error = RuntimeError.new("boom").tap { |raised| raised.set_backtrace(["config.ru:1"]) }
      problem = {
        type: "about:blank",
        title: "Internal Server Error",
        status: 500,
        detail: "RuntimeError: boom",
        backtrace: ["config.ru:1"]
      }

      expected = [500, { "content-type" => "application/problem+json" }, [JSON.generate(problem)]]

      assert_equal expected, reloader(world_with(error)).call(env)
    end

    it "answers a SyntaxError, which isn't a StandardError, the same way" do
      assert_equal 500, reloader(world_with(SyntaxError.new("unexpected end"))).call(env).first
    end

    it "shows a message that isn't valid UTF-8 with its bad bytes replaced" do
      body = reloader(world_with(RuntimeError.new(+"bad \xFF byte"))).call(env).last.first

      assert_equal "RuntimeError: bad � byte", JSON.parse(body)["detail"]
    end

    it "answers a failed load with an empty body for HEAD" do
      assert_equal [], reloader(world_with(RuntimeError.new("boom"))).call(env.merge("REQUEST_METHOD" => "HEAD")).last
    end

    it "keeps answering with the error until a file changes" do
      world = world_with(RuntimeError.new("boom"), app("second"))
      served = reloader(world)
      world.now = 1.0

      assert_equal [500, 1], [served.call(env).first, world.loads]
    end

    it "recovers on the next change after a failed load" do
      world = world_with(app("first"), RuntimeError.new("boom"), app("third"))
      served = reloader(world)
      world.change
      body(served)
      world.change

      assert_equal "third", body(served)
    end
  end
end
