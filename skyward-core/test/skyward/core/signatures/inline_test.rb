# frozen_string_literal: true

require 'fileutils'
require 'test_helper'
require 'tmpdir'

describe Skyward::Core::Signatures::Inline do
  let(:calls) { [] }

  def write(directory, file, source)
    path = File.join(directory, file)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def app(files = {})
    Dir.mktmpdir do |directory|
      files.each { |file, source| write(directory, file, source) }
      yield directory
    end
  end

  # Writes what rbs-inline would into the --output directory, and answers as it would.
  def capture(generates: {}, answer: ['', true])
    lambda do |env, command, chdir|
      calls << [env, command, chdir]
      output = command.find { |arg| arg.start_with?('--output=') }.to_s.delete_prefix('--output=')
      generates.each { |file, source| write(output, file, source) }
      answer
    end
  end

  def generated(directory) = Skyward::Core::Signatures::Inline.rbs_files(File.join(directory, 'sig/generated'))

  describe '.generate' do
    def generate(directory, rbs_inline: '/gems/rbs-inline', **answers)
      Skyward::Core::Signatures::Inline.generate(directory, rbs_inline:, capture: capture(**answers))
    end

    it "does nothing, and says nothing, when the bundle doesn't have rbs-inline" do
      app('app.rb' => '', 'sig/generated/app.rbs' => 'old') do |directory|
        assert_equal [nil, [], { 'app.rbs' => 'old' }],
                     [generate(directory, rbs_inline: nil), calls, generated(directory)]
      end
    end

    it "runs rbs-inline, opt-in, in the directory, on the app's Ruby, into a scratch directory" do
      app('app.rb' => '', 'lib/a.rb' => '', 'test/a_test.rb' => '') do |directory|
        generate(directory)
        env, (ruby, rbs_inline, output, *paths), chdir = calls.fetch(0)
        scratch = output.delete_prefix('--output=')

        assert_equal [{}, Gem.ruby, '/gems/rbs-inline', %w[app.rb lib], directory, false],
                     [env, ruby, rbs_inline, paths, chdir, File.exist?(scratch)]
      end
    end

    it "returns rbs-inline's output, and leaves sig/generated alone, when it fails" do
      app('app.rb' => '', 'sig/generated/app.rbs' => 'old') do |directory|
        result = generate(directory, generates: { 'app.rbs' => 'new' }, answer: ["app.rb: can't read\n", false])

        assert_equal ["rbs-inline couldn't regenerate sig/generated:\napp.rb: can't read\n", { 'app.rbs' => 'old' }],
                     [result, generated(directory)]
      end
    end

    it 'writes what rbs-inline generates to sig/generated, however deep' do
      app('app.rb' => '') do |directory|
        result = generate(directory, generates: { 'app.rbs' => 'app', 'todos/todo.rbs' => 'todo' })

        assert_equal [nil, { 'app.rbs' => 'app', 'todos/todo.rbs' => 'todo' }], [result, generated(directory)]
      end
    end

    it 'writes only the files whose content changed' do
      app('app.rb' => '', 'sig/generated/app.rbs' => 'app', 'sig/generated/todo.rbs' => 'old') do |directory|
        path = File.join(directory, 'sig/generated/app.rbs')
        File.utime(Time.at(0), Time.at(0), path)
        generate(directory, generates: { 'app.rbs' => 'app', 'todo.rbs' => 'new' })

        assert_equal [Time.at(0), { 'app.rbs' => 'app', 'todo.rbs' => 'new' }], [File.mtime(path), generated(directory)]
      end
    end

    it 'removes the files rbs-inline no longer generates, and the directories that leaves empty' do
      files = { 'app.rb' => '', 'sig/generated/app.rbs' => 'app', 'sig/generated/gone/deep/gone.rbs' => 'gone' }
      app(files) do |directory|
        generate(directory, generates: { 'app.rbs' => 'app' })

        assert_equal [{ 'app.rbs' => 'app' }, false],
                     [generated(directory), File.exist?(File.join(directory, 'sig/generated/gone'))]
      end
    end

    it 'makes no sig/generated when rbs-inline generates nothing' do
      app('app.rb' => '') do |directory|
        generate(directory)

        refute_path_exists File.join(directory, 'sig/generated')
      end
    end
  end

  describe '.sources' do
    it 'lists each .rb file and each directory holding one, outside test/, spec/, vendor/, tmp/ and hidden ones' do
      files = %w[
        boot.rb app.rb Gemfile modules/notes.rb lib/deep/a.rb db/schema.sql test/a_test.rb spec/a_spec.rb
        vendor/bundle/a.rb tmp/a.rb .bundle/a.rb
      ].to_h { |file| [file, ''] }

      app(files) do |directory|
        assert_equal %w[app.rb boot.rb lib modules], Skyward::Core::Signatures::Inline.sources(directory)
      end
    end
  end

  describe '.rbs_files' do
    it 'reads every .rbs file under the directory, however deep, by its path there' do
      app('a.rbs' => 'a', 'b/c.rbs' => 'c', 'b/d.rb' => 'd') do |directory|
        assert_equal({ 'a.rbs' => 'a', 'b/c.rbs' => 'c' }, Skyward::Core::Signatures::Inline.rbs_files(directory))
      end
    end

    it "reads nothing from a directory that doesn't exist" do
      app { |directory| assert_empty Skyward::Core::Signatures::Inline.rbs_files(File.join(directory, 'missing')) }
    end
  end
end
