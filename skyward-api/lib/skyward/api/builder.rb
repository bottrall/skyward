# frozen_string_literal: true

class Skyward::API::Builder
  Mount = Data.define(
    :api, #: Skyward::API
    :at #: String
  )

  Use = Data.define(
    :middleware, #: Skyward::API::_Middleware
    :args, #: Array[untyped]
    :kwargs, #: Hash[Symbol, untyped]
    :block #: (^(?) -> untyped)?
  )

  # @dynamic mounts
  attr_reader :mounts #: Array[Mount]

  # @dynamic middleware
  attr_reader :middleware #: Array[Use]

  # @rbs return: void
  def initialize
    @mounts = []
    @middleware = []
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

  # @rbs (Skyward::API::_Middleware middleware, *untyped args, **untyped kwargs) ?{ (?) -> untyped } -> void
  def use(middleware, *args, **kwargs, &block)
    @middleware = [*@middleware, Use.new(middleware:, args:, kwargs:, block:)]
  end
end
