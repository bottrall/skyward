# frozen_string_literal: true

# rbs_inline: enabled

class Bench::Task < Skyward::ORM::Record
  table :bench_tasks

  # @dynamic id, title, done, due_on, created_at, score
  attr_reader :id          #: Integer
  attr_reader :title       #: String
  attr_reader :done        #: bool
  attr_reader :due_on      #: Date?
  attr_reader :created_at  #: Time
  attr_reader :score       #: Float
end
