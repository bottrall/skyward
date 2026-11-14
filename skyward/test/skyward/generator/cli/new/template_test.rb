# frozen_string_literal: true

require 'skyward/generator'
require 'test_helper'

describe Skyward::Generator::CLI::New::Template do
  template = Skyward::Generator::CLI::New::Template

  describe '.files' do
    it "writes the app's code, its tests, its tooling, its agent instructions and empty modules/ and db/migrate/" do
      paths = %w[
        .gitignore AGENTS.md Gemfile Rakefile Steepfile app.rb bin/ci bin/setup bin/test boot.rb config.ru
        db/migrate/.keep lib/health_api.rb modules/.keep rbs_collection.yaml sig/generated/app.rbs
        sig/generated/boot.rbs sig/generated/health_api.rbs test/app_test.rb test/lib/health_api_test.rb
        test/test_helper.rb
      ]

      assert_equal paths.sort, template.files('todos').keys.sort
    end

    it 'names the default database after the app' do
      assert_includes template.files('my_app').fetch('boot.rb'), '/db/my_app.sqlite3'
    end

    it 'titles the app with its name camelized' do
      assert_includes template.files('my_app').fetch('app.rb'), "Skyward.app(docs: true, title: 'MyApp')"
    end

    it 'pins skyward at the running version' do
      assert_includes template.files('todos').fetch('Gemfile'), "gem 'skyward', '= #{Skyward::VERSION}'"
    end

    it 'fills in every placeholder' do
      assert_empty(template.files('todos').select { |_path, content| content.match?(template::PLACEHOLDER) })
    end
  end
end
