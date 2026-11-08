# frozen_string_literal: true

Todo = Data.define(
  :id,        #: Integer
  :title,     #: String
  :priority,  #: :low | :normal | :high
  :due_on,    #: Date?
  :done       #: bool
)
