# frozen_string_literal: true

require 'test_helper'

describe Skyward::Core::CLI::Registry do
  let(:registry) { Skyward::Core::CLI::Registry.new }

  describe '#register' do
    it 'raises naming a command registered twice' do
      registry.register('routes', 'List every route') { |_args| nil }

      assert_raises_with_message(ArgumentError, 'a command named routes is already registered') do
        registry.register('routes', 'Something else') { |_args| nil }
      end
    end

    it 'adds a command under its name' do
      registry.register('routes', 'List every route') { |_args| nil }

      assert_equal 'List every route', registry.find('routes')&.description
    end
  end

  describe '#find' do
    it 'returns nil for a name with no command' do
      assert_nil registry.find('routes')
    end
  end

  describe '#commands' do
    it 'lists every command sorted by name' do
      registry.register('routes', 'List every route') { |_args| nil }
      registry.register('migrate', 'Run the pending migrations') { |_args| nil }

      assert_equal %w[migrate routes], registry.commands.map(&:name)
    end
  end
end
