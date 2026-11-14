# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'test_helper'
require 'tmpdir'

describe Skyward::ORM::CLI::Rollback do
  runner = Skyward::ORM::Migrations::Runner

  let(:kernel) do
    Class.new do
      attr_reader :aborted

      def abort(message) = @aborted = message
    end.new
  end
  let(:out) { StringIO.new }
  let(:empty) { TestDatabase.empty }

  define_method(:app) do |migrations = {}, &block|
    Dir.mktmpdir do |tmp|
      directory = File.realpath(tmp)
      File.write(
        File.join(directory, 'boot.rb'),
        "Skyward.connect(#{empty.url.inspect}, signatures: #{File.join(directory, 'sig').inspect})\n"
      )
      FileUtils.mkdir_p(File.join(directory, 'db/migrate'))
      migrations.each { |file, sql| File.write(File.join(directory, 'db/migrate', file), sql) }
      connection = empty.connect
      runner.run(empty.adapter, connection, runner.read(File.join(directory, 'db/migrate')))
      block.call(directory, connection)
    ensure
      $LOADED_FEATURES.delete(File.join(directory, 'boot.rb'))
    end
  end

  def run_in(directory, generate: -> {})
    Skyward::ORM::CLI::Rollback.run(directory:, out:, kernel:, session: Skyward::ORM::Connection::SESSION, generate:)
  end

  describe '.run' do
    it "fails with why sig/generated couldn't be regenerated, before it rolls back" do
      app('20261001000000_create_a.sql' => "CREATE TABLE a (id INTEGER);\n-- down\nDROP TABLE a;\n") do |directory|
        run_in(directory, generate: -> { "rbs-inline couldn't regenerate sig/generated:\n" })

        assert_equal ["rbs-inline couldn't regenerate sig/generated:\n", ''], [kernel.aborted, out.string]
      end
    end

    it "rolls back the latest migration in db/migrate on boot.rb's database, printing its version" do
      migrations = {
        '20261001000000_create_a.sql' => "CREATE TABLE a (id INTEGER);\n-- down\nDROP TABLE a;\n",
        '20261002000000_create_b.sql' => "CREATE TABLE b (id INTEGER);\n-- down\nDROP TABLE b;\n"
      }
      app(migrations) do |directory, connection|
        run_in(directory)

        assert_equal ["Rolled back 20261002000000\n", nil, [['20261001000000']]],
                     [out.string, kernel.aborted, connection.execute('SELECT version FROM schema_migrations')]
      end
    end

    it "fails with only why it can't roll back" do
      app do |directory|
        run_in(directory)

        assert_equal [runner.rollback_message(:nothing), ''], [kernel.aborted, out.string]
      end
    end
  end
end
