# frozen_string_literal: true

require "test_helper"

describe Skyward::Test::Client do
  def sent(verb = :get, path = "/", **options)
    env = nil
    app = lambda do |request|
      env = request
      [200, {}, []]
    end
    Skyward::Test::Client.new(app).public_send(verb, path, **options)
    env
  end

  def response(headers: {}, body: [])
    Skyward::Test::Client.new(->(_env) { [201, headers, body] }).get("/")
  end

  let(:closable) do
    Class.new do
      attr_reader :closed

      def initialize(*chunks)
        @chunks = chunks
      end

      def each(&) = @chunks.each(&)

      def close
        @closed = true
      end
    end
  end

  it "is frozen" do
    assert_predicate Skyward::Test::Client.new(->(_env) {}), :frozen?
  end

  describe "requests" do
    it "sends each method by its name" do
      methods = %i[get post put patch delete head options].map { |verb| sent(verb)["REQUEST_METHOD"] }

      assert_equal %w[GET POST PUT PATCH DELETE HEAD OPTIONS], methods
    end

    it "sends no body without json:" do
      env = sent(:post)

      assert_equal ["", nil, nil], [env["rack.input"].read, env["CONTENT_TYPE"], env["CONTENT_LENGTH"]]
    end

    it "sends json: as a JSON body, as binary" do
      input = sent(:post, "/", json: { title: "Café" })["rack.input"].read

      assert_equal '{"title":"Café"}'.b, input
    end

    it "labels a json: body with its content type and length" do
      env = sent(:post, "/", json: { title: "Café" })

      assert_equal ["application/json", "17"], env.values_at("CONTENT_TYPE", "CONTENT_LENGTH")
    end

    it "lets headers: override json:'s content type" do
      env = sent(:post, "/", json: {}, headers: { "content-type" => "application/vnd.todo+json" })

      assert_equal "application/vnd.todo+json", env["CONTENT_TYPE"]
    end

    it "sends cookies: as a cookie header" do
      env = sent(:get, "/", cookies: { "session" => "abc", "theme" => "dark" })

      assert_equal "session=abc; theme=dark", env["HTTP_COOKIE"]
    end

    it "sends no cookie header without cookies:" do
      refute sent.key?("HTTP_COOKIE")
    end

    it "splits the query string from the path" do
      env = sent(:get, "/todos?done=true&limit=5")

      assert_equal ["/todos", "done=true&limit=5"], env.values_at("PATH_INFO", "QUERY_STRING")
    end

    it "sends an empty query string when the path has none" do
      assert_equal ["/todos", ""], sent(:get, "/todos").values_at("PATH_INFO", "QUERY_STRING")
    end

    it "sends the CGI and Rack variables Rack 3 requires" do
      keys = %w[SCRIPT_NAME SERVER_NAME SERVER_PORT SERVER_PROTOCOL rack.url_scheme]

      assert_equal ["", "localhost", "80", "HTTP/1.1", "http"], sent.values_at(*keys)
    end

    it "sends headers: by their HTTP names" do
      env = sent(:get, "/", headers: { "authorization" => "Bearer x", "x-request-id" => "42" })

      assert_equal ["Bearer x", "42"], env.values_at("HTTP_AUTHORIZATION", "HTTP_X_REQUEST_ID")
    end

    it "sends a content-type or content-length header without the HTTP_ prefix" do
      env = sent(:post, "/", headers: { "content-type" => "text/plain", "content-length" => "0" })

      keys = %w[CONTENT_TYPE CONTENT_LENGTH HTTP_CONTENT_TYPE HTTP_CONTENT_LENGTH]

      assert_equal ["text/plain", "0", nil, nil], env.values_at(*keys)
    end
  end

  describe "responses" do
    it "is frozen" do
      assert_predicate response, :frozen?
    end

    it "has the status and headers as the app returned them" do
      headers = { "x-total" => "3", "set-cookie" => %w[a=1 b=2] }

      answered = response(headers:)

      assert_equal [201, headers], [answered.status, answered.headers]
    end

    it "reads the whole body as text" do
      assert_equal "Hello, ruby", response(body: ["Hello", ", ", "ruby"]).body
    end

    it "closes a body that responds to close" do
      body = closable.new("Hello")
      response(body:)

      assert body.closed
    end

    it "closes the body even when reading it raises" do
      body = closable.new
      def body.each = raise("connection reset")
      assert_raises(RuntimeError) { response(body:) }

      assert body.closed
    end
  end

  describe "#json on a response" do
    it "is the body parsed with Symbol keys when the content type is JSON" do
      parsed = response(headers: { "content-type" => "application/json" }, body: ['{"todo":{"id":1}}']).json

      assert_equal({ todo: { id: 1 } }, parsed)
    end

    it "is parsed for a +json content type with parameters" do
      headers = { "content-type" => "application/problem+json; charset=utf-8" }
      parsed = response(headers:, body: ['{"status":404}']).json

      assert_equal({ status: 404 }, parsed)
    end

    it "is nil when the content type isn't JSON" do
      assert_nil response(headers: { "content-type" => "text/json-ish" }, body: ['{"id":1}']).json
    end

    it "is nil without a content type" do
      assert_nil response(body: ['{"id":1}']).json
    end

    it "is nil when the body is empty" do
      assert_nil response(headers: { "content-type" => "application/json" }).json
    end
  end
end
