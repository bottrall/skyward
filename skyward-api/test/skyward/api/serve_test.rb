# frozen_string_literal: true

require "test_helper"
require "fileutils"
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

        def exec(*args, **options) = @calls << [:exec, *args, options]
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

    it "runs one Falcon process, from the directory, on localhost and PORT, in development" do
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
          Skyward::API::Serve::RACKUP,
          { chdir: directory }
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

  describe ".reloader" do
    # Rack::Builder.parse_file's part, without Rack: config.ru's `run` names the app.
    let(:build) do
      rackup = Class.new do
        attr_reader :app

        def run(app)
          @app = app
        end
      end
      ->(config) { rackup.new.tap { |builder| builder.instance_eval(File.read(config), config, 1) }.app }
    end

    after do
      registered_loaders.select { |loader| loader.dirs.any? { |dir| dir.start_with?(@directory) } }.each(&:unregister)
      $LOADED_FEATURES.reject! { |feature| feature.start_with?(@directory) }
      %i[ServeReloadHello ServeReloadAdmin ServeReloadStaff].each do |name|
        Object.send(:remove_const, name) if Object.const_defined?(name)
      end
    end

    # As serve.ru lists them.
    def registered_loaders = Zeitwerk::Registry.loaders.enum_for(:each).to_a

    # Reopened, not redefined, on every reload, unless a Zeitwerk loader unloads it.
    def hello(path, name = "ServeReloadHello", keyword: nil) = <<~RUBY
      class #{name} < Skyward::API
        description "Says hello."

        get #{path.inspect}, to: :greet

        def greet#{"(#{keyword})" if keyword} = { message: "Hello" }
      end
    RUBY

    def signature(name = "ServeReloadHello", keyword: nil)
      namespace = "module #{name.split("::").first}\nend\n\n" if name.include?("::")
      "#{namespace}class #{name} < Skyward::API\n  def greet: (#{keyword}) -> { message: String }\nend\n"
    end

    # Tests don't run in the app's directory, and the request logs would land among their output.
    def skyward_app(mount) = %(Skyward.app(signatures: "\#{__dir__}/sig", logger: nil) { |app| app.mount #{mount} })

    def config(at)
      %(require_relative "hello"\nrun #{skyward_app("ServeReloadHello.new, at: #{at.inspect}")}\n)
    end

    def zeitwerk_config(api = "ServeReloadHello") = <<~RUBY
      require "zeitwerk"

      loader = Zeitwerk::Loader.new
      loader.push_dir("\#{__dir__}/lib")
      loader.enable_reloading
      loader.setup

      run #{skyward_app("#{api}.new")}
    RUBY

    def app(files = { "hello.rb" => hello("/hello"), "sig/hello.rbs" => signature, "config.ru" => config("/") })
      Dir.mktmpdir do |tmp|
        @directory = File.realpath(tmp)
        files.each { |file, source| write(file, source) }
        @now = 0.0
        yield Skyward::API::Serve.reloader(
          @directory,
          build:,
          clock: -> { @now },
          apis: -> { ObjectSpace.each_object(Skyward::API.singleton_class).to_a },
          features: $LOADED_FEATURES,
          loaders: -> { registered_loaders }
        )
      end
    end

    def write(file, source)
      path = File.join(@directory, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, source)
    end

    # Each edit gets a later modification time, and comes after the reloader last looked.
    def edit(file, source)
      write(file, source)
      @now += 1
      File.utime(Time.at(@now), Time.at(@now), File.join(@directory, file))
    end

    def remove(file)
      File.delete(File.join(@directory, file))
      @now += 1
    end

    def status(app, path) = app.call({ "REQUEST_METHOD" => "GET", "PATH_INFO" => path }).first

    it "serves the app config.ru builds" do
      app { |served| assert_equal 200, status(served, "/hello") }
    end

    it "answers a changed route after a reload" do
      app do |served|
        edit("hello.rb", hello("/hi"))

        assert_equal 200, status(served, "/hi")
      end
    end

    it "no longer answers a removed route after a reload" do
      app do |served|
        edit("hello.rb", hello("/hi"))

        assert_equal 404, status(served, "/hello")
      end
    end

    it "boots a new app with a changed signature" do
      app do |served|
        edit("hello.rb", hello("/hello", keyword: 'name: "you"'))
        stale = status(served, "/hello")
        edit("sig/hello.rbs", signature(keyword: "?name: String"))

        assert_equal [500, 200], [stale, status(served, "/hello")]
      end
    end

    it "builds a new app from a changed config.ru" do
      app do |served|
        edit("config.ru", config("/v2"))

        assert_equal 200, status(served, "/v2/hello")
      end
    end

    describe "an app that sets up its own Zeitwerk loader" do
      let(:files) do
        { "config.ru" => zeitwerk_config, "lib/serve_reload_hello.rb" => hello("/hello"), "sig/hello.rbs" => signature }
      end

      it "reloads it change after change" do
        app(files) do |served|
          edit("lib/serve_reload_hello.rb", hello("/hi"))
          hi = status(served, "/hi")
          edit("lib/serve_reload_hello.rb", hello("/hey"))

          assert_equal [200, 200, 404], [hi, status(served, "/hey"), status(served, "/hi")]
        end
      end

      it "recovers once a class that failed to load is fixed" do
        app(files) do |served|
          edit("lib/serve_reload_hello.rb", "class ServeReloadHello < Skyward::API\n")
          broken = status(served, "/hello")
          edit("lib/serve_reload_hello.rb", hello("/hello"))

          assert_equal [500, 200], [broken, status(served, "/hello")]
        end
      end

      it "recovers once a file that failed the loader's setup is fixed" do
        app(files) do |served|
          edit("lib/my-thing.rb", "")
          broken = status(served, "/hello")
          remove("lib/my-thing.rb")
          fixed = status(served, "/hello")
          edit("lib/serve_reload_hello.rb", hello("/hi"))

          assert_equal [500, 200, 200], [broken, fixed, status(served, "/hi")]
        end
      end

      it "keeps reloading after a namespace is renamed" do
        admin = {
          "config.ru" => zeitwerk_config("ServeReloadAdmin::Users"),
          "lib/serve_reload_admin/users.rb" => hello("/hello", "ServeReloadAdmin::Users"),
          "sig/hello.rbs" => signature("ServeReloadAdmin::Users")
        }
        app(admin) do |served|
          File.rename(File.join(@directory, "lib/serve_reload_admin"), File.join(@directory, "lib/serve_reload_staff"))
          edit("lib/serve_reload_staff/users.rb", hello("/hello", "ServeReloadStaff::Users"))
          edit("sig/hello.rbs", signature("ServeReloadStaff::Users"))
          edit("config.ru", zeitwerk_config("ServeReloadStaff::Users"))
          renamed = status(served, "/hello")
          edit("lib/serve_reload_staff/users.rb", hello("/hi", "ServeReloadStaff::Users"))

          assert_equal [200, 200], [renamed, status(served, "/hi")]
        end
      end
    end
  end

  describe ".watch" do
    def watch(*files)
      Dir.mktmpdir do |directory|
        files.each do |file|
          path = File.join(directory, file)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, "")
        end
        yield directory, Skyward::API::Serve.watch(directory)
      end
    end

    it "watches .rb, .rbs and config.ru files, however deep" do
      files = %w[app.rb config.ru Gemfile README.md lib/config.ru lib/todos/todo.rb lib/todos/todo.erb sig/todo.rbs]

      watch(*files) do |_directory, watched|
        assert_equal %w[app.rb config.ru lib/config.ru lib/todos/todo.rb sig/todo.rbs], watched.keys.sort
      end
    end

    it "leaves out tmp/, log/, vendor/, node_modules/ and hidden directories" do
      files = %w[app.rb tmp/a.rb log/a.rb vendor/bundle/a.rb node_modules/a/a.rb .git/a.rb .bundle/a.rb]

      watch(*files) { |_directory, watched| assert_equal %w[app.rb], watched.keys }
    end

    it "gives each file's modification time" do
      watch("app.rb") do |directory, watched|
        assert_equal({ "app.rb" => File.mtime(File.join(directory, "app.rb")) }, watched)
      end
    end
  end

  describe ".unload" do
    let(:fake_loader) do
      Class.new do
        attr_reader :dirs, :calls

        def initialize(dirs, reloading: true)
          @dirs = dirs
          @reloading = reloading
          @calls = []
        end

        def reloading_enabled? = @reloading

        def reload = @calls << :reload

        def setup = @calls << :setup

        def unload = @calls << :unload

        def unregister = @calls << :unregister
      end
    end

    after do
      %i[ServeUnloadTodos ServeUnloadDone ServeUnloadVendored ServeUnloadGone].each do |name|
        Object.send(:remove_const, name) if Object.const_defined?(name)
      end
    end

    def unload(directory = "/app", apis: [], features: [], loaders: [])
      Skyward::API::Serve.unload(directory, apis:, features:, loaders:)
    end

    # Requires each file from a new directory, so the classes it defines have their source there.
    def defined_in(files)
      Dir.mktmpdir do |tmp|
        directory = File.realpath(tmp)
        files.each do |file, source|
          path = File.join(directory, file)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, source)
          require path
          $LOADED_FEATURES.delete(path)
        end
        yield directory
      end
    end

    def refusal
      yield
      nil
    rescue Skyward::BootError => e
      e.message
    end

    it "refuses an app's Zeitwerk loader without reloading enabled, saying how to fix it" do
      message = refusal { unload(loaders: [fake_loader.new(%w[/app/lib], reloading: false)]) }

      assert_equal "skyward serve can't reload the Zeitwerk loader for /app/lib. Call `loader.enable_reloading` " \
                   "before `loader.setup` in development, then restart skyward serve.",
                   message
    end

    it "changes nothing when it refuses" do
      features = %w[/app/app.rb]
      loader = fake_loader.new(%w[/app/lib])
      refusal { unload(features:, loaders: [loader, fake_loader.new(%w[/app/admin], reloading: false)]) }

      assert_equal [%w[/app/app.rb], []], [features, loader.calls]
    end

    it "clears the routes and description of every API class defined in the directory" do
      source = <<~RUBY
        class ServeUnloadTodos < Skyward::API
          description "Things to do."
          get "/", to: :index
        end

        class ServeUnloadDone < ServeUnloadTodos
          get "/done", to: :done
        end
      RUBY
      defined_in("app.rb" => source) do |directory|
        unload(directory, apis: [ServeUnloadTodos, ServeUnloadDone])

        assert_equal [[], nil, []],
                     [ServeUnloadTodos.routes, ServeUnloadTodos.class_description, ServeUnloadDone.routes]
      end
    end

    it "leaves alone an API class defined under an ignored directory, or outside the directory" do
      source = %(class ServeUnloadVendored < Skyward::API\n  get "/", to: :index\nend\n)
      defined_in("vendor/bundle/vendored.rb" => source) do |directory|
        outside = Class.new(Skyward::API) { get "/", to: :index }
        Object.const_set(:ServeUnloadTodos, outside)
        unload(directory, apis: [ServeUnloadVendored, ServeUnloadTodos])

        assert_equal [1, 1], [ServeUnloadVendored.routes.size, ServeUnloadTodos.routes.size]
      end
    end

    it "leaves alone an API class with no name, or named under an anonymous module" do
      anonymous = Class.new(Skyward::API) { get "/", to: :index }
      nested = Module.new.const_set(:Todos, Class.new(Skyward::API) { get "/", to: :index })
      unload(apis: [anonymous, nested])

      assert_equal [1, 1], [anonymous.routes.size, nested.routes.size]
    end

    it "leaves alone an API class whose constant, or its namespace, is gone" do
      gone = Object.const_set(:ServeUnloadGone, Class.new(Skyward::API) { get "/", to: :index })
      Object.send(:remove_const, :ServeUnloadGone)
      namespace = Object.const_set(:ServeUnloadGone, Module.new)
      nested = namespace.const_set(:Todos, Class.new(Skyward::API) { get "/", to: :index })
      Object.send(:remove_const, :ServeUnloadGone)
      unload(apis: [gone, nested])

      assert_equal [1, 1], [gone.routes.size, nested.routes.size]
    end

    it "drops the app's files from the loaded features" do
      features = %w[/app/app.rb /app/lib/todo.rb /gems/rack/lib/rack.rb /application/app.rb]
      unload(features:)

      assert_equal %w[/gems/rack/lib/rack.rb /application/app.rb], features
    end

    it "keeps the features under tmp/, log/, vendor/, node_modules/ and hidden directories" do
      ignored = %w[/app/tmp/a.rb /app/log/a.rb /app/vendor/bundle/a.rb /app/node_modules/a.rb /app/.bundle/a.rb]
      features = ignored.dup
      unload(features:)

      assert_equal ignored, features
    end

    it "unloads and unregisters a Zeitwerk loader whose directories are all the app's" do
      loader = fake_loader.new(%w[/app /app/lib])
      unload(loaders: [loader])

      assert_equal %i[setup unload unregister], loader.calls
    end

    it "reloads any other Zeitwerk loader with reloading enabled" do
      loaders = [%w[/app/lib /gems/todos/lib], %w[/app/vendor/bundle/todos/lib], []].map do |dirs|
        fake_loader.new(dirs)
      end
      unload(loaders:)

      assert_equal [[:reload]] * 3, loaders.map(&:calls)
    end

    it "leaves any other Zeitwerk loader without reloading alone" do
      loader = fake_loader.new(%w[/gems/todos/lib], reloading: false)
      unload(loaders: [loader])

      assert_empty loader.calls
    end
  end
end
