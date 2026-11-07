# frozen_string_literal: true

# Orphan deliberately has no Ruby class; the reader never looks up the classes it can't read.
module ReaderFixtures
  API = Class.new
  Child = Class.new
  Holder = Class.new
  NewTodo = Data.define(:title, :priority)
  Node = Class.new
  NotAClass = Module.new
  Outer = Class.new
  Pair = Class.new
  Parent = Class.new
  Todo = Class.new
end
