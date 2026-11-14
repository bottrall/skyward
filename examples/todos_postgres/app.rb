# frozen_string_literal: true

# rbs_inline: enabled

require_relative 'boot'

App = Skyward.app(docs: true, title: 'Todos') do |app|
  app.mount HealthAPI.new
  app.mount Todos::API.new(todos: Todos::Service), at: '/todos'
end #: Skyward::API::_RackApp
