# frozen_string_literal: true

class Skyward::API::LineLogger
  # @rbs @io: IO

  # @rbs io: IO
  # @rbs return: void
  def initialize(io)
    @io = io
    freeze
  end

  # @rbs message: String
  # @rbs return: void
  def info(message)
    @io.write("#{message}\n")
    # $stdout is block-buffered when it isn't a terminal, which would hold lines back from a log collector.
    @io.flush
  end
end
