# frozen_string_literal: true

require "skyward/api"
require_relative "todos_api"

App = Skyward.app { |app| app.mount TodosAPI.new(todos: nil), at: "/todos" }
