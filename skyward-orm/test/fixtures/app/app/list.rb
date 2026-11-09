# frozen_string_literal: true

class List < Skyward::ORM::Record
  table :lists

  attr_reader :id, :name
end
