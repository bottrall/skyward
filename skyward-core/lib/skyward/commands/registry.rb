# frozen_string_literal: true

class Skyward::Commands::Registry
  # @rbs @commands: Hash[String, Command]

  Command = Data.define(
    :name, #: String
    :description, #: String
    :action #: ^(Array[String]) -> void
  )

  # @rbs return: void
  def initialize
    @commands = {}
  end

  # @rbs name: String
  # @rbs description: String
  # @rbs &action: (Array[String]) -> void
  # @rbs return: void
  def register(name, description, &action)
    raise ArgumentError, "a command named #{name} is already registered" if @commands.key?(name)

    @commands[name] = Command.new(name:, description:, action:)
  end

  # @rbs name: String
  # @rbs return: Command?
  def find(name) = @commands[name]

  # @rbs return: Array[Command]
  def commands = @commands.values.sort_by(&:name)
end
