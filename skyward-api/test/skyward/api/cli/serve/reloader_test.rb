# frozen_string_literal: true

require "test_helper"

describe Skyward::API::CLI::Serve::Reloader do
  let(:fake_world) do
    Class.new do
      attr_accessor :now, :files, :failures
      attr_reader :loads, :watches, :log

      def initialize(loads)
        @now = 0.0
        @files = { "app.rb" => Time.at(0) }
        @pending = loads
        @failures = []
        @loads = 0
        @watches = 0
        @log = []
      end

      def watch
        @watches += 1
        case @files
        when Exception then raise @files
        else @files
        end
      end

      def load
        @loads += 1
        @log << :load
        case (result = @pending.shift)
        when Exception then raise result
        when Thread::Queue then result.pop
        else result
        end
      end

      def generate
        @log << :generate
        case (result = @failures.shift)
        when Exception then raise result
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
    Skyward::API::CLI::Serve::Reloader.new(
      watch: world.method(:watch),
      load: world.method(:load),
      generate: world.method(:generate),
      clock: -> { world.now }
    )
  end

  def body(reloader) = reloader.call(env).last.first

  def detail(reloader) = JSON.parse(body(reloader))["detail"]

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

    it "regenerates sig/generated before it loads, when it's created and once a .rb file changed" do
      world = world_with(app("first"), app("second"))
      served = reloader(world)
      world.change
      body(served)

      assert_equal %i[generate load generate load], world.log
    end

    it "regenerates once a .rb file is added or removed" do
      world = world_with(app("first"), app("second"), app("third"))
      served = reloader(world)
      world.now = 1.0
      world.files = { "app.rb" => Time.at(0), "new.rb" => Time.at(0) }
      body(served)
      world.now = 2.0
      world.files = { "new.rb" => Time.at(0) }
      body(served)

      assert_equal %i[generate load generate load generate load], world.log
    end

    it "doesn't regenerate without a .rb file among the changes" do
      world = world_with(app("first"), app("second"))
      world.files = { "config.ru" => Time.at(0) }
      served = reloader(world)
      world.change
      body(served)

      assert_equal %i[load load], world.log
    end

    it "answers with the development 500 carrying rbs-inline's output, without loading, when it can't regenerate" do
      failure = "rbs-inline couldn't regenerate sig/generated:\napp.rb: can't read\n"
      world = world_with(app("first"))
      world.failures = [failure]
      problem = JSON.parse(body(reloader(world)))

      assert_equal ["Skyward::Core::BootError: #{failure}", [], 0],
                   [problem["detail"], problem["backtrace"], world.loads]
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
      assert_equal "RuntimeError: bad � byte", detail(reloader(world_with(RuntimeError.new(+"bad \xFF byte"))))
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

  describe "#regenerate" do
    it "regenerates sig/generated once a .rb file changed, and leaves the reload to the next request" do
      world = world_with(app("first"), app("second"))
      served = reloader(world)
      world.change
      served.regenerate
      regenerated = world.log.dup

      assert_equal [%i[generate load generate], "second", %i[generate load generate load]],
                   [regenerated, body(served), world.log]
    end

    it "doesn't regenerate when no .rb file changed" do
      world = world_with(app("first"))
      world.files = { "app.rb" => Time.at(0), "sig/app.rbs" => Time.at(0) }
      served = reloader(world)
      world.files = { "app.rb" => Time.at(0), "sig/app.rbs" => Time.at(1) }
      served.regenerate

      assert_equal %i[generate load], world.log
    end

    it "has the next request answer with the development 500 when it can't regenerate" do
      world = world_with(app("first"), app("second"))
      world.failures = [nil, "rbs-inline couldn't regenerate sig/generated:\napp.rb: can't read\n"]
      served = reloader(world)
      world.change
      served.regenerate

      assert_equal "Skyward::Core::BootError: rbs-inline couldn't regenerate sig/generated:\napp.rb: can't read\n",
                   detail(served)
    end

    it "has the next reload regenerate again when regenerating raised, and answer with its error" do
      world = world_with(app("first"), app("second"))
      world.failures = [nil, Errno::EACCES.new("sig/generated"), Errno::EACCES.new("sig/generated")]
      served = reloader(world)
      world.change
      served.regenerate

      assert_equal ["Errno::EACCES: Permission denied - sig/generated", %i[generate load generate generate]],
                   [detail(served), world.log]
    end

    it "keeps working after a file is removed while it's watched" do
      world = world_with(app("first"))
      served = reloader(world)
      world.files = Errno::ENOENT.new("app.rb")
      served.regenerate
      world.files = { "app.rb" => Time.at(1) }
      served.regenerate

      assert_equal %i[generate load generate], world.log
    end

    it "waits for a reload in progress, then doesn't regenerate what it regenerated" do
      gate = Thread::Queue.new
      world = world_with(app("first"), gate)
      served = reloader(world)
      world.change
      reloading = Thread.new { body(served) }
      Thread.pass while reloading.status == "run"
      regenerating = Thread.new { served.regenerate }
      Thread.pass while regenerating.status == "run"
      waited = regenerating.status
      gate << app("second")
      [reloading, regenerating].each(&:join)

      assert_equal ["sleep", %i[generate load generate load]], [waited, world.log]
    end
  end
end
