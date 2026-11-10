# frozen_string_literal: true

# rbs_inline: enabled

class Todos::Record < Skyward::ORM::Record
  # @rbs!
  #   type priority = :low | :normal | :high

  table :todos
  references :list_id, Lists::Record, on_delete: :cascade
  default priority: :normal, done: false
  check :title, length: 1..200
  index :list_id, :done

  # @dynamic id, list_id, title, priority, due_on, done
  attr_reader :id        #: Integer
  attr_reader :list_id   #: Integer?
  attr_reader :title     #: String
  attr_reader :priority  #: priority
  attr_reader :due_on    #: Date?
  attr_reader :done      #: bool
end
