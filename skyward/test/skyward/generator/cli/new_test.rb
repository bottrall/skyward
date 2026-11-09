# frozen_string_literal: true

require "fileutils"
require "skyward/generator"
require "stringio"
require "test_helper"
require "tmpdir"

describe Skyward::Generator::CLI::New do
  usage = "skyward: new takes one NAME, the app's directory.\nUsage: skyward new NAME [--skip-bundle]"
  exists = "skyward: todos already exists and isn't an empty directory."
  next_step = "Next: cd todos && bin/setup\n"
  files = Skyward::Generator::CLI::New::Template.files("todos")

  let(:bundled) { true }
  let(:kernel) do
    Class.new do
      attr_reader :calls

      def initialize(bundled)
        @bundled = bundled
        @calls = []
      end

      def abort(message) = @calls << [:abort, message]

      def system(*command, **options)
        @calls << [:system, *command, options]
        @bundled
      end
    end.new(bundled)
  end
  let(:out) { StringIO.new }
  let(:directory) { Dir.mktmpdir("skyward-new") }

  after { FileUtils.rm_rf(directory) }

  def run_new(*args) = Skyward::Generator::CLI::New.run(args, directory:, out:, kernel:)

  def written
    root = File.join(directory, "todos")
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root).select { |path| File.file?(File.join(root, path)) }
       .to_h { |path| [path, File.read(File.join(root, path))] }
  end

  describe ".run" do
    it "fails saying what it takes when given no name, writing nothing" do
      run_new("--skip-bundle")

      assert_equal [[[:abort, usage]], []], [kernel.calls, Dir.children(directory)]
    end

    it "fails saying what it takes when given more than one name, writing nothing" do
      run_new("todos", "--skip-bundel")

      assert_equal [[[:abort, usage]], []], [kernel.calls, Dir.children(directory)]
    end

    it "fails saying what a name needs when it isn't lowercase, writing nothing" do
      message = "skyward: My-App can't name an app. Use lowercase letters, digits and underscores, " \
                "starting with a letter, as in my_app."
      run_new("My-App")

      assert_equal [[[:abort, message]], []], [kernel.calls, Dir.children(directory)]
    end

    it "fails when the directory has files, writing nothing" do
      FileUtils.mkdir_p(File.join(directory, "todos"))
      File.write(File.join(directory, "todos", "notes.txt"), "Mine\n")
      run_new("todos")

      assert_equal [[[:abort, exists]], { "notes.txt" => "Mine\n" }], [kernel.calls, written]
    end

    it "fails when a file has the name, writing nothing" do
      File.write(File.join(directory, "todos"), "Mine\n")
      run_new("todos")

      assert_equal [[[:abort, exists]], "Mine\n"], [kernel.calls, File.read(File.join(directory, "todos"))]
    end

    it "writes the app into an empty directory of that name" do
      FileUtils.mkdir_p(File.join(directory, "todos"))
      run_new("todos", "--skip-bundle")

      assert_equal files, written
    end

    it "writes the template's files for the name, listing each" do
      run_new("--skip-bundle", "todos")

      assert_equal [files, files.keys.map { |path| "Wrote todos/#{path}\n" }.join],
                   [written, out.string.delete_suffix(next_step)]
    end

    it "makes the scripts in bin/ executable, and nothing else" do
      run_new("todos", "--skip-bundle")
      executable, others = files.keys.partition { |path| File.executable?(File.join(directory, "todos", path)) }

      assert_equal [files.keys.grep(%r{\Abin/}).sort, false], [executable.sort, others.empty?]
    end

    it "says what's next without installing the gems when given --skip-bundle" do
      run_new("todos", "--skip-bundle")

      assert_equal [[], next_step], [kernel.calls, out.string.lines.last]
    end

    it "installs the gems in the app's directory, then says what's next" do
      run_new("todos")
      bundle = [:system, "bundle", "install", { chdir: File.join(directory, "todos") }]

      assert_equal [[bundle], next_step], [kernel.calls, out.string.lines.last]
    end

    describe "when bundle install fails" do
      let(:bundled) { false }

      it "fails saying how to finish" do
        run_new("todos")
        message = "skyward: bundle install failed in todos. Fix what it printed, then run bin/setup there."

        assert_equal [:abort, message], kernel.calls.last
      end
    end
  end
end
