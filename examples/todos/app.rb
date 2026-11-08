# frozen_string_literal: true

require "skyward/api"
require_relative "health_api"
require_relative "todo_store"
require_relative "todos_api"

App = Skyward.app(docs: true, title: "Todos") do |app|
  todos = TodoStore.new

  app.mount HealthAPI.new
  app.mount TodosAPI.new(todos:), at: "/todos"
end #: Skyward::API::_RackApp
