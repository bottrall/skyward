# config.ru
require "skyward/api"

class Hello < Skyward::API
  get "/hello/:name", to: :greet

  def greet(name:, shout: "false")
    message = "Hello, #{name}"
    { message: shout == "true" ? message.upcase : message }
  end
end

run Skyward.app { |app| app.mount Hello.new }
