# frozen_string_literal: true

class Skyward::API::Router
  Endpoint = Data.define(
    :verb, #: String
    :pattern, #: Array[String | Symbol]
    :api, #: Skyward::API
    :to #: Symbol
  )

  Match = Data.define(
    :api, #: Skyward::API
    :to, #: Symbol
    :params #: Hash[Symbol, String]
  )

  ESCAPE = /%\h\h/ #: Regexp

  METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze #: Array[String]

  # @rbs @endpoints: Array[Endpoint]

  # @rbs mounts: Array[Skyward::API::Builder::Mount]
  # @rbs return: void
  def initialize(mounts)
    @endpoints = mounts.flat_map { |mount| endpoints(mount) }
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

  # @rbs mount: Skyward::API::Builder::Mount
  # @rbs return: Array[Endpoint]
  def endpoints(mount)
    mount.api.class.routes.map do |route|
      Endpoint.new(
        verb: route.verb.upcase.name,
        pattern: pattern(full_path(mount.at, route.path)),
        api: mount.api,
        to: route.to
      )
    end
  end

  # @rbs prefix: String
  # @rbs path: String
  # @rbs return: String
  def full_path(prefix, path)
    parts = [prefix, path].map { |part| part.delete_prefix("/").delete_suffix("/") }
    "/#{parts.reject(&:empty?).join("/")}"
  end

  # @rbs path: String
  # @rbs return: Array[String | Symbol]
  def pattern(path)
    path.split("/", -1).map { |segment| segment.start_with?(":") ? segment.delete_prefix(":").to_sym : segment }
  end

  # @rbs endpoint: Endpoint
  # @rbs verb: String
  # @rbs segments: Array[String]
  # @rbs return: Match?
  def match_endpoint(endpoint, verb, segments)
    return unless endpoint.verb == verb

    params = params_for(endpoint.pattern, segments)
    Match.new(api: endpoint.api, to: endpoint.to, params:) if params
  end

  # @rbs pattern: Array[String | Symbol]
  # @rbs segments: Array[String]
  # @rbs return: Hash[Symbol, String]?
  def params_for(pattern, segments)
    return unless pattern.length == segments.length

    pairs = segments.zip(pattern)
    return unless pairs.all? { |segment, part| part.is_a?(Symbol) ? !segment.empty? : segment == part }

    pairs.filter_map { |segment, part| [part, decode(segment)] if part.is_a?(Symbol) }.to_h
  end

  # Lenient, unlike URI.decode_uri_component, because servers pass the path
  # through undecoded and a malformed escape is the client's to send.
  # @rbs segment: String
  # @rbs return: String
  def decode(segment)
    segment.b.gsub(ESCAPE) { |escape| escape.delete_prefix("%").hex.chr }.force_encoding(Encoding::UTF_8)
  end
end
