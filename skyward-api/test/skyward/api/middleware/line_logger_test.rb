# frozen_string_literal: true

require 'test_helper'

describe Skyward::API::Middleware::LineLogger do
  let(:io) do
    Struct.new(:calls) do
      def write(text) = calls << [:write, text]

      def flush = calls << [:flush]
    end.new([])
  end

  it 'is frozen' do
    assert_predicate Skyward::API::Middleware::LineLogger.new(io), :frozen?
  end

  describe '#info' do
    it 'writes the message alone as one line, then flushes it' do
      Skyward::API::Middleware::LineLogger.new(io).info('{"status":200}')

      assert_equal [[:write, %({"status":200}\n)], [:flush]], io.calls
    end
  end
end
