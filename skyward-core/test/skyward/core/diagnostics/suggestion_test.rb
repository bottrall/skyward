# frozen_string_literal: true

require 'test_helper'

describe Skyward::Core::Diagnostics::Suggestion do
  suggestion = Skyward::Core::Diagnostics::Suggestion

  it 'is the closest of the names to a misspelt one' do
    assert_equal 'Integer', suggestion.closest('Integr', %w[String Integer Float])
  end

  it 'is nil when no name is close' do
    assert_nil suggestion.closest('Todo', %w[String Integer Float])
  end
end
