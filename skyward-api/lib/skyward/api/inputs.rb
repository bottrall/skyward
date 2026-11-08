# frozen_string_literal: true

require "json"
require "uri"

class Skyward::API::Inputs
  # @rbs!
  #   type refusal = :content_too_large | :unsupported_media_type
  #   type body = Coercer::result | refusal | nil

  JSON_TYPE = %r{\A(?:application/json|[^/;\s]+/[^/;\s]+\+json)\s*(?:;|\z)}i #: Regexp

  MALFORMED_QUERY = Coercer::Invalid.new(
    errors: [Coercer::Error.new(at: "query", message: "is not a valid query string")]
  ) #: Coercer::Invalid

  INVALID_JSON = Coercer::Invalid.new(
    errors: [Coercer::Error.new(at: "body", message: "is not valid JSON")]
  ) #: Coercer::Invalid

  # @rbs @keywords: Array[[Skyward::API::Routing::Router::Keyword, Coercer::t]]
  # @rbs @providers: Array[Skyward::API::Routing::Router::Provider]
  # @rbs @body: bool
  # @rbs @request: bool
  # @rbs @max_body_size: Integer

  # @rbs keywords: Array[Skyward::API::Routing::Router::Keyword]
  # @rbs providers: Array[Skyward::API::Routing::Router::Provider]
  # @rbs max_body_size: Integer
  # @rbs return: void
  def initialize(keywords, providers:, max_body_size:)
    requested, coerced = keywords.partition { |keyword| keyword.source == :request }
    @keywords = coerced.map { |keyword| [keyword, Coercer.compile(keyword.type, strings: keyword.source != :body)] }
    @providers = providers
    @body = coerced.any? { |keyword| keyword.source == :body }
    @request = requested.any?
    @max_body_size = max_body_size
    freeze
  end

  # Providers run first, so a caller they turn away learns nothing from the inputs' problems.
  # @rbs env: Hash[String, untyped]
  # @rbs params: Hash[Symbol, String]
  # @rbs return: Coercer::result | refusal | Skyward::rack
  def call(env, params)
    request = Skyward::Request.new(env) if @request || @providers.any?
    none = {} #: Hash[Symbol, untyped]
    provided = request ? provide(@providers, request, none) : none
    return provided if provided.is_a?(Array)

    given = @request ? { **provided, request: } : provided
    body = body(env) if @body
    case body
    when Symbol then body
    else arguments(params, query(env["QUERY_STRING"].to_s), body, given)
    end
  end

  private

  # @rbs providers: Array[Skyward::API::Routing::Router::Provider]
  # @rbs request: Skyward::Request
  # @rbs values: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped] | Skyward::rack
  def provide(providers, request, values)
    provider, *rest = providers
    return values unless provider

    value = provider.callable.call(request)
    if Skyward::API::Serializer::RESPONSES.any? { |klass| value.is_a?(klass) }
      provider.serializer.call(value)
    else
      provide(rest, request, { **values, provider.name => value })
    end
  end

  # @rbs params: Hash[Symbol, String]
  # @rbs query: Hash[String, String | Array[String]] | Coercer::Invalid
  # @rbs body: Coercer::result?
  # @rbs given: Hash[Symbol, untyped]
  # @rbs return: Coercer::result
  def arguments(params, query, body, given)
    coerced = @keywords.filter_map { |keyword, coercer| argument(keyword, coercer, params, query, body) }
    results = [*coerced, *given.map { |name, value| [name, Coercer::Ok.new(value:)] }]
    combined = Coercer.combine(results.to_h)
    case combined
    # A malformed query string is every query keyword's error, but one problem,
    # and each keyword can find up to MAX_ERRORS.
    when Coercer::Invalid
      combined.with(errors: combined.errors.uniq.first(Coercer::MAX_ERRORS))
    else combined
    end
  end

  # @rbs keyword: Skyward::API::Routing::Router::Keyword
  # @rbs coercer: Coercer::t
  # @rbs params: Hash[Symbol, String]
  # @rbs query: Hash[String, String | Array[String]] | Coercer::Invalid
  # @rbs body: Coercer::result?
  # @rbs return: [Symbol, Coercer::result]?
  def argument(keyword, coercer, params, query, body)
    name = keyword.name
    at = keyword.source == :body ? "body" : "#{keyword.source}.#{name}"
    raw =
      case keyword.source
      when :path then Coercer::Ok.new(value: params.fetch(name))
      when :query then from_query(query, name.to_s)
      else body
      end
    result =
      case raw
      when Coercer::Ok then coercer.call(raw.value, at)
      when Coercer::Invalid then raw
      else Coercer.absent(keyword.type, keyword.required, at)
      end
    [name, result] if result
  end

  # @rbs query: Hash[String, String | Array[String]] | Coercer::Invalid
  # @rbs key: String
  # @rbs return: Coercer::result?
  def from_query(query, key)
    case query
    when Coercer::Invalid then query
    else (Coercer::Ok.new(value: query.fetch(key)) if query.key?(key))
    end
  end

  # @rbs string: String
  # @rbs return: Hash[String, String | Array[String]] | Coercer::Invalid
  def query(string)
    URI.decode_www_form(string).group_by(&:first).transform_values do |named|
      named.size == 1 ? named.fetch(0).last : named.map(&:last)
    end
  # URI.decode_www_form raises for a byte outside ASCII, which a client can send unescaped.
  rescue ArgumentError
    MALFORMED_QUERY
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: body
  def body(env)
    return :content_too_large if env["CONTENT_LENGTH"].to_i > @max_body_size

    # One byte past the limit shows the body runs past it, without reading the rest.
    text = env["rack.input"]&.read(@max_body_size + 1).to_s
    return :content_too_large if text.bytesize > @max_body_size
    return if text.empty?
    return :unsupported_media_type unless JSON_TYPE.match?(env["CONTENT_TYPE"].to_s)

    parse(String.new(text, encoding: Encoding::UTF_8))
  end

  # @rbs text: String
  # @rbs return: Coercer::result
  def parse(text)
    # JSON.parse lets through bytes that aren't UTF-8, which JSON forbids.
    return INVALID_JSON unless text.valid_encoding?

    Coercer::Ok.new(value: JSON.parse(text))
  rescue JSON::ParserError
    INVALID_JSON
  end
end
