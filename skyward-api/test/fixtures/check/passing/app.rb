# frozen_string_literal: true

# rbs_inline: enabled

require "skyward/api"

class Hello < Skyward::API
  get "/", to: :greet

  # @rbs return: { message: String }
  def greet = { message: "Hello" }
end

App = Skyward.app(logger: nil) { |app| app.mount Hello.new }
