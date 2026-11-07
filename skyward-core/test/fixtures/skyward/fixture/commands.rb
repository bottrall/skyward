# frozen_string_literal: true

Skyward::Commands.register("greet", "Greet whoever's named") do |args|
  puts "Hello, #{args.join(" and ")}!"
end
