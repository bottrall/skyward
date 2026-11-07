# frozen_string_literal: true

module Skyward::Commands
  extend self

  REGISTRY = Registry.new #: Registry

  # @rbs name: String
  # @rbs description: String
  # @rbs &: (Array[String]) -> void
  # @rbs return: void
  def register(name, description, &) = REGISTRY.register(name, description, &)

  # @rbs paths: Array[String]
  # @rbs return: Array[String]
  def first_per_gem(paths) = paths.uniq { |path| File.basename(File.dirname(path)) }

  # @rbs (Array[String] argv, registry: Registry, out: _Writer) -> Integer
  def run(argv, registry:, out:)
    name, *args = argv
    case name
    when nil, "help", "--help", "-h"
      out.write(help(registry))
      0
    else
      command = registry.find(name)
      if command
        command.action.call(args)
        0
      else
        out.write("skyward: no command named #{name}\n", help(registry))
        1
      end
    end
  end

  private

  # @rbs registry: Registry
  # @rbs return: String
  def help(registry)
    commands = registry.commands
    width = commands.map { |command| command.name.length }.max || 0
    rows = commands.map { |command| "  #{command.name.ljust(width)}  #{command.description}\n" }
    ["Usage: skyward COMMAND [ARGS]\n", *rows].join
  end
end
