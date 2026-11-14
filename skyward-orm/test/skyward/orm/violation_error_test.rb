# frozen_string_literal: true

require 'test_helper'

describe Skyward::ORM::ViolationError do
  violation = Skyward::ORM::Violation.new(
    kind: :unique,
    constraint: 'lists_name_key',
    columns: [:name],
    message: 'UNIQUE constraint failed: lists.name'
  )

  it "carries the violation, with the database's message" do
    error = Skyward::ORM::ViolationError.new(violation)

    assert_equal [violation, 'UNIQUE constraint failed: lists.name'], [error.violation, error.message]
  end
end
