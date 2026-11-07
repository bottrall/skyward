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

  Static = Data.define(
    :prefix, #: String
    :from #: String
  )

  # @dynamic mounts
  attr_reader :mounts #: Array[Mount]

  # @dynamic middleware
  attr_reader :middleware #: Array[Use]

  # @dynamic statics
  attr_reader :statics #: Array[Static]

  # @rbs return: void
  def initialize
    @mounts = []
    @middleware = []
    @statics = []
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

  # @rbs prefix: String
  # @rbs from: String
  # @rbs return: void
  def static(prefix, from:)
    directory = File.expand_path(from)
    raise Skyward::BootError, "static #{prefix.inspect}: no directory at #{directory}" unless File.directory?(directory)

    @statics = [*@statics, Static.new(prefix:, from: directory)]
  end
end
