# frozen_string_literal: true

# rbs_inline: enabled

class Lists::Record < Skyward::ORM::Record
  table :lists

  # @dynamic id, name
  attr_reader :id    #: Integer
  attr_reader :name  #: String
end
