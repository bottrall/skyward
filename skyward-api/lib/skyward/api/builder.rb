# frozen_string_literal: true

class Skyward::API::Builder
  Mount = Data.define(
    :api, #: Skyward::API
    :at #: String
  )

  # @dynamic mounts
  attr_reader :mounts #: Array[Mount]

  # @rbs return: void
  def initialize
    @mounts = []
  end

  # @rbs api: Skyward::API
  # @rbs at: String
  # @rbs return: void
  def mount(api, at: "/")
    # Steep proves a typed caller passes an API, but an untyped one can pass anything.
    unless api.is_a?(Skyward::API) # steep:ignore UnreachableBranch
      raise Skyward::BootError, "mount takes a Skyward::API instance, got #{api.inspect}"
    end

    @mounts = [*@mounts, Mount.new(api:, at:)]
  end
end
