# frozen_string_literal: true

require "json"
require "uri"

class Skyward::API::Inputs
  # @rbs!
  #   type refusal = :content_too_large | :unsupported_media_type
  #   type body = Skyward::API::Coercer::result | refusal | nil

  JSON_TYPE = %r{\A(?:application/json|[^/;\s]+/[^/;\s]+\+json)\s*(?:;|\z)}i #: Regexp

  MALFORMED_QUERY = Skyward::API::Coercer::Invalid.new(
    errors: [Skyward::API::Coercer::Error.new(at: "query", message: "is not a valid query string")]
  ) #: Skyward::API::Coercer::Invalid

  INVALID_JSON = Skyward::API::Coercer::Invalid.new(
    errors: [Skyward::API::Coercer::Error.new(at: "body", message: "is not valid JSON")]
  ) #: Skyward::API::Coercer::Invalid

  # @rbs @keywords: Array[[Skyward::API::Router::Keyword, Skyward::API::Coercer::t]]
  # @rbs @body: bool
  # @rbs @request: bool
  # @rbs @max_body_size: Integer

  # @rbs keywords: Array[Skyward::API::Router::Keyword]
  # @rbs max_body_size: Integer
  # @rbs return: void
  def initialize(keywords, max_body_size:)
    requested, coerced = keywords.partition { |keyword| keyword.source == :request }
    @keywords = coerced.map do |keyword|
      [keyword, Skyward::API::Coercer.compile(keyword.type, strings: keyword.source != :body)]
    end
    @body = coerced.any? { |keyword| keyword.source == :body }
    @request = requested.any?
    @max_body_size = max_body_size
    freeze
  end

  # @rbs env: Hash[String, untyped]
  # @rbs params: Hash[Symbol, String]
  # @rbs return: Skyward::API::Coercer::result | refusal
  def call(env, params)
    body = body(env) if @body
    request = Skyward::Request.new(env) if @request
    case body
    when Symbol then body
    else arguments(params, query(env["QUERY_STRING"].to_s), body, request)
    end
  end

  private

  # @rbs params: Hash[Symbol, String]
  # @rbs query: Hash[String, String | Array[String]] | Skyward::API::Coercer::Invalid
  # @rbs body: Skyward::API::Coercer::result?
  # @rbs request: Skyward::Request?
  # @rbs return: Skyward::API::Coercer::result
  def arguments(params, query, body, request)
    coerced = @keywords.filter_map { |keyword, coercer| argument(keyword, coercer, params, query, body) }
    results = request ? [*coerced, [:request, Skyward::API::Coercer::Ok.new(value: request)]] : coerced
    combined = Skyward::API::Coercer.combine(results.to_h)
    case combined
    # A malformed query string is every query keyword's error, but one problem,
    # and each keyword can find up to MAX_ERRORS.
    when Skyward::API::Coercer::Invalid
      combined.with(errors: combined.errors.uniq.first(Skyward::API::Coercer::MAX_ERRORS))
    else combined
    end
  end

  # @rbs keyword: Skyward::API::Router::Keyword
  # @rbs coercer: Skyward::API::Coercer::t
  # @rbs params: Hash[Symbol, String]
  # @rbs query: Hash[String, String | Array[String]] | Skyward::API::Coercer::Invalid
  # @rbs body: Skyward::API::Coercer::result?
  # @rbs return: [Symbol, Skyward::API::Coercer::result]?
  def argument(keyword, coercer, params, query, body)
    name = keyword.name
    at = keyword.source == :body ? "body" : "#{keyword.source}.#{name}"
    raw =
      case keyword.source
      when :path then Skyward::API::Coercer::Ok.new(value: params.fetch(name))
      when :query then from_query(query, name.to_s)
      else body
      end
    result =
      case raw
      when Skyward::API::Coercer::Ok then coercer.call(raw.value, at)
      when Skyward::API::Coercer::Invalid then raw
      else Skyward::API::Coercer.absent(keyword.type, keyword.required, at)
      end
    [name, result] if result
  end

  # @rbs query: Hash[String, String | Array[String]] | Skyward::API::Coercer::Invalid
  # @rbs key: String
  # @rbs return: Skyward::API::Coercer::result?
  def from_query(query, key)
    case query
    when Skyward::API::Coercer::Invalid then query
    else (Skyward::API::Coercer::Ok.new(value: query.fetch(key)) if query.key?(key))
    end
  end

  # @rbs string: String
  # @rbs return: Hash[String, String | Array[String]] | Skyward::API::Coercer::Invalid
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
  # @rbs return: Skyward::API::Coercer::result
  def parse(text)
    # JSON.parse lets through bytes that aren't UTF-8, which JSON forbids.
    return INVALID_JSON unless text.valid_encoding?

    Skyward::API::Coercer::Ok.new(value: JSON.parse(text))
  rescue JSON::ParserError
    INVALID_JSON
  end
end
