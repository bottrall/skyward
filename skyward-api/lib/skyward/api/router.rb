# frozen_string_literal: true

class Skyward::API::Router
  # @rbs! type returned = Skyward::Types::t | Created | Response | Rack

  Keyword = Data.define(
    :name, #: Symbol
    :source, #: :path | :query | :body
    :required, #: bool
    :type #: Skyward::Types::t
  )

  # Skyward::Created[T], which the reader can't read, so its value's type is read on its own.
  Created = Data.define(
    :type #: Skyward::Types::t
  )

  Response = Data.define(
    :klass #: Class
  )

  Rack = Data.define

  Endpoint = Data.define(
    :verb, #: String
    :pattern, #: Array[String | Symbol]
    :api, #: Skyward::API
    :to, #: Symbol
    :keywords, #: Array[Keyword]
    :returns, #: Array[returned]
    :inputs, #: Skyward::API::Inputs
    :serializer #: Skyward::API::Serializer
  )

  Match = Data.define(
    :api, #: Skyward::API
    :to, #: Symbol
    :inputs, #: Skyward::API::Inputs
    :params, #: Hash[Symbol, String]
    :serializer #: Skyward::API::Serializer
  )

  METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze #: Array[String]

  # @rbs @endpoints: Array[Endpoint]

  # @rbs endpoints: Array[Endpoint]
  # @rbs return: void
  def initialize(endpoints)
    @endpoints = endpoints
  end

  # @rbs verb: String
  # @rbs path: String
  # @rbs return: Match?
  def match(verb, path)
    segments = path.split("/", -1)
    routed = verb == "HEAD" ? "GET" : verb
    @endpoints.lazy.filter_map { |endpoint| match_endpoint(endpoint, routed, segments) }.first
  end

  # @rbs path: String
  # @rbs return: Array[String]
  def allowed(path)
    segments = path.split("/", -1)
    verbs = @endpoints.filter_map { |endpoint| endpoint.verb if params_for(endpoint.pattern, segments) }
    return [] if verbs.empty?

    implied = verbs.include?("GET") ? %w[HEAD OPTIONS] : %w[OPTIONS]
    METHODS & (verbs + implied)
  end

  private

  # @rbs endpoint: Endpoint
  # @rbs verb: String
  # @rbs segments: Array[String]
  # @rbs return: Match?
  def match_endpoint(endpoint, verb, segments)
    return unless endpoint.verb == verb

    params = params_for(endpoint.pattern, segments)
    return unless params

    Match.new(api: endpoint.api, to: endpoint.to, inputs: endpoint.inputs, params:, serializer: endpoint.serializer)
  end

  # @rbs pattern: Array[String | Symbol]
  # @rbs segments: Array[String]
  # @rbs return: Hash[Symbol, String]?
  def params_for(pattern, segments)
    return unless pattern.length == segments.length

    pairs = segments.zip(pattern)
    return unless pairs.all? { |segment, part| part.is_a?(Symbol) ? !segment.empty? : segment == part }

    pairs.filter_map do |segment, part|
      [part, Skyward::API::PercentEncoding.decode(segment)] if part.is_a?(Symbol)
    end.to_h
  end
end
