# frozen_string_literal: true

# rbs_inline: enabled

require "skyward/api"

class Hello < Skyward::API
  get "/", to: :greet

  def greet = { message: "Hello" }

  # @rbs return: Integer
  def count = "many"
end

App = Skyward.app(strict: false, logger: nil) { |app| app.mount Hello.new }
