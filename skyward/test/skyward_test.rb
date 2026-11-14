# frozen_string_literal: true

require 'test_helper'

describe Skyward do
  it 'loads Skyward API and Skyward ORM at its own version' do
    assert_equal [Skyward::VERSION] * 2, [Skyward::API::VERSION, Skyward::ORM::VERSION]
  end
end
