# frozen_string_literal: true

require "json"
require "stringio"

class Skyward::Test::Client
  Response = Data.define(
    :status, #: Integer
    :headers, #: Hash[String, String | Array[String]]
    :body, #: String
    :json #: untyped
  )

  JSON_TYPE = %r{\A[^/;\s]+/(?:[^;\s]+\+)?json\s*(?:;|\z)}i #: Regexp

  # Rack takes these two headers without the HTTP_ prefix the others get.
  UNPREFIXED = %w[CONTENT_TYPE CONTENT_LENGTH].freeze #: Array[String]

  # @rbs @app: Skyward::Test::_App

  # @rbs (Skyward::Test::_App app) -> void
  def initialize(app)
    @app = app
    freeze
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def get(path, json: nil, headers: {}, cookies: {})
    request("GET", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def post(path, json: nil, headers: {}, cookies: {})
    request("POST", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def put(path, json: nil, headers: {}, cookies: {})
    request("PUT", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def patch(path, json: nil, headers: {}, cookies: {})
    request("PATCH", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def delete(path, json: nil, headers: {}, cookies: {})
    request("DELETE", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def head(path, json: nil, headers: {}, cookies: {})
    request("HEAD", path, json, headers, cookies)
  end

  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def options(path, json: nil, headers: {}, cookies: {})
    request("OPTIONS", path, json, headers, cookies)
  end

  private

  # @rbs method: String
  # @rbs path: String
  # @rbs json: untyped
  # @rbs headers: Hash[String, String]
  # @rbs cookies: Hash[String, String]
  # @rbs return: Response
  def request(method, path, json, headers, cookies)
    body = json.nil? ? "" : JSON.generate(json)
    sent = body_headers(body).merge(cookie_header(cookies), headers)
    status, response_headers, response_body = @app.call(env(method, path, body, sent))
    text = read(response_body)
    Response.new(status:, headers: response_headers, body: text, json: parse(response_headers["content-type"], text))
  end

  # @rbs body: String
  # @rbs return: Hash[String, String]
  def body_headers(body)
    body.empty? ? {} : { "content-type" => "application/json", "content-length" => body.bytesize.to_s }
  end

  # @rbs cookies: Hash[String, String]
  # @rbs return: Hash[String, String]
  def cookie_header(cookies)
    cookies.empty? ? {} : { "cookie" => cookies.map { |name, value| "#{name}=#{value}" }.join("; ") }
  end

  # @rbs method: String
  # @rbs path: String
  # @rbs body: String
  # @rbs headers: Hash[String, String]
  # @rbs return: Hash[String, untyped]
  def env(method, path, body, headers)
    path_info, _, query = path.partition("?")
    {
      "REQUEST_METHOD" => method,
      "SCRIPT_NAME" => "",
      "PATH_INFO" => path_info,
      "QUERY_STRING" => query,
      "SERVER_NAME" => "localhost",
      "SERVER_PORT" => "80",
      "SERVER_PROTOCOL" => "HTTP/1.1",
      "rack.url_scheme" => "http",
      "rack.input" => StringIO.new(body.b),
      "rack.errors" => StringIO.new
    }.merge(headers.to_h { |name, value| [env_key(name), value] })
  end

  # @rbs name: String
  # @rbs return: String
  def env_key(name)
    key = name.upcase.tr("-", "_")
    UNPREFIXED.include?(key) ? key : "HTTP_#{key}"
  end

  # @rbs body: untyped
  # @rbs return: String
  def read(body)
    body.enum_for(:each).to_a.join
  ensure
    body.close if body.respond_to?(:close)
  end

  # @rbs content_type: untyped
  # @rbs body: String
  # @rbs return: untyped
  def parse(content_type, body)
    JSON.parse(body, symbolize_names: true) if JSON_TYPE.match?(content_type) && !body.empty?
  end
end
