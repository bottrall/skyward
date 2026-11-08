# frozen_string_literal: true

NewTodo = Data.define(
  :title,     #: String
  :priority,  #: :low | :normal | :high
  :due_on     #: Date?
)
