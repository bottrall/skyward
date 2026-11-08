# frozen_string_literal: true

require "stringio"
require "test_helper"

describe Skyward::API::Inputs do
  types = Skyward::Types

  integer = types::Scalar.new(name: :integer)
  string = types::Scalar.new(name: :string)
  title = types::Record.new(fields: [types::Field.new(name: :title, type: string, required: true)])

  def keyword(name, source, type, required: true)
    Skyward::API::Router::Keyword.new(name:, source:, required:, type:)
  end

  def inputs(*keywords, providers: []) = Skyward::API::Inputs.new(keywords, providers:, max_body_size: 16)

  def env(query: nil, body: nil, type: "application/json", length: nil)
    {
      "QUERY_STRING" => query,
      "CONTENT_TYPE" => type,
      "CONTENT_LENGTH" => length,
      "rack.input" => StringIO.new(body.to_s)
    }.compact
  end

  def ok(value) = Skyward::API::Coercer::Ok.new(value:)

  def invalid(*errors)
    Skyward::API::Coercer::Invalid.new(
      errors: errors.map { |at, message| Skyward::API::Coercer::Error.new(at:, message:) }
    )
  end

  it "is frozen" do
    assert_predicate inputs, :frozen?
  end

  describe "#call" do
    describe "a path parameter" do
      let(:id) { inputs(keyword(:id, :path, integer)) }

      it "comes from the path, parsed" do
        assert_equal ok({ id: 42 }), id.call(env, { id: "42" })
      end

      it "is reported at path. and its name" do
        assert_equal invalid(["path.id", 'expected Integer, got "x"']), id.call(env, { id: "x" })
      end
    end

    describe "a query keyword" do
      let(:limit) { inputs(keyword(:limit, :query, integer)) }

      it "comes from the query string, parsed" do
        assert_equal ok({ limit: 50 }), limit.call(env(query: "limit=50&page=2"), {})
      end

      it "takes an array from repeated keys" do
        tags = inputs(keyword(:tag, :query, types::ArrayOf.new(type: string)))

        assert_equal ok({ tag: ["a b", "c"] }), tags.call(env(query: "tag=a+b&tag=c"), {})
      end

      it "doesn't take tag[] as tag" do
        tags = inputs(keyword(:tag, :query, types::ArrayOf.new(type: string), required: false))

        assert_equal ok({}), tags.call(env(query: "tag[]=a"), {})
      end

      it "takes an empty value as a value" do
        assert_equal invalid(["query.limit", 'expected Integer, got ""']), limit.call(env(query: "limit="), {})
      end

      it "is required when it has no default" do
        assert_equal invalid(["query.limit", "is required"]), limit.call(env, {})
      end

      it "isn't passed when it's optional and absent" do
        assert_equal ok({}), inputs(keyword(:limit, :query, integer, required: false)).call(env, {})
      end

      it "refuses a query string with bytes outside ASCII once, beside the other keywords' problems" do
        all = inputs(keyword(:id, :path, integer), keyword(:limit, :query, integer), keyword(:page, :query, integer))
        expected = invalid(["path.id", 'expected Integer, got "x"'], ["query", "is not a valid query string"])

        assert_equal expected, all.call(env(query: "limit=é"), { id: "x" })
      end
    end

    describe "body:" do
      let(:body) { inputs(keyword(:body, :body, title)) }

      it "isn't read for an endpoint without one" do
        request = env(body: "{}")
        result = inputs.call(request, {})

        assert_equal [ok({}), 0], [result, request["rack.input"].pos]
      end

      it "comes from the JSON body" do
        assert_equal ok({ body: { title: "Go" } }), body.call(env(body: '{"title":"Go"}'), {})
      end

      it "is reported at body." do
        assert_equal invalid(["body.title", "is required"]), body.call(env(body: "{}"), {})
      end

      it "refuses a Content-Length over the limit without reading the body" do
        request = env(body: "{}", length: "17")
        body.call(request, {})

        assert_equal 0, request["rack.input"].pos
      end

      it "answers a Content-Length over the limit as content too large" do
        assert_equal :content_too_large, body.call(env(body: "{}", length: "17"), {})
      end

      it "is absent when the request has no input stream" do
        assert_equal invalid(["body", "is required"]), body.call({}, {})
      end

      it "reads no more than one byte past the limit" do
        request = env(body: '{"title":"Ship it now"}')
        body.call(request, {})

        assert_equal 17, request["rack.input"].pos
      end

      it "answers a body that runs past the limit as content too large" do
        assert_equal :content_too_large, body.call(env(body: '{"title":"Ship it now"}'), {})
      end

      it "takes a body exactly at the limit" do
        assert_equal ok({ body: { title: "Ship" } }), body.call(env(body: '{"title":"Ship"}'), {})
      end

      it "is required when there's no body and it has no default" do
        assert_equal invalid(["body", "is required"]), body.call(env, {})
      end

      it "isn't passed when there's no body and it's optional" do
        assert_equal ok({}), inputs(keyword(:body, :body, title, required: false)).call(env, {})
      end

      it "answers a content type other than JSON as unsupported" do
        assert_equal :unsupported_media_type, body.call(env(body: "title=Ship", type: "text/plain"), {})
      end

      it "answers a body with no content type as unsupported" do
        assert_equal :unsupported_media_type, body.call(env(body: "{}", type: nil), {})
      end

      it "takes a content type ending in +json, with parameters" do
        json = env(body: '{"title":"Go"}', type: "application/merge-patch+json; charset=utf-8")

        assert_equal ok({ body: { title: "Go" } }), body.call(json, {})
      end

      it "refuses a body that isn't UTF-8" do
        assert_equal invalid(["body", "is not valid JSON"]), body.call(env(body: "\"\xFF\"".b), {})
      end

      it "refuses a body that isn't JSON" do
        assert_equal invalid(["body", "is not valid JSON"]), body.call(env(body: "{title"), {})
      end
    end

    describe "request:" do
      let(:request_type) { Skyward::API::Boot::REQUEST_TYPE }

      it "is the request, built from the env and never from the query string" do
        request = env(query: "request=x").merge("skyward.request_id" => "abc-123")
        passed = inputs(keyword(:request, :request, request_type)).call(request, {}).value.fetch(:request)

        assert_equal [Skyward::Request, request], [passed.class, passed.env]
      end

      it "is passed even when it has a default" do
        request = env.merge("skyward.request_id" => "abc-123")
        passed = inputs(keyword(:request, :request, request_type, required: false)).call(request, {})

        assert_equal [:request], passed.value.keys
      end
    end

    describe "a provided keyword" do
      let(:trail) { [] }
      let(:requested) { env.merge("skyward.request_id" => "abc-123") }
      let(:unauthorized) { provider(:current_user, ->(_request) { Skyward.unauthorized("Sign in first") }) }

      def provider(name, callable)
        responses = [Skyward::API::Router::Response.new(klass: Skyward::Unauthorized)]
        serializer = Skyward::API::Serializer.new(responses, label: "The :#{name} provider")
        Skyward::API::Router::Provider.new(name:, callable:, value: nil, responses:, serializer:)
      end

      def traced(name)
        callable = lambda do |_request|
          trail << name
          name
        end
        provider(name, callable)
      end

      it "is its provider's value for the request, never the query string" do
        current_user = provider(:current_user, ->(request) { request.headers["authorization"] })
        request = requested.merge("QUERY_STRING" => "current_user=mallory", "HTTP_AUTHORIZATION" => "Bearer ada")

        assert_equal ok({ current_user: "Bearer ada" }), inputs(providers: [current_user]).call(request, {})
      end

      it "runs each provider once, in the method's order" do
        inputs(providers: [traced(:tenant), traced(:current_user)]).call(requested, {})

        assert_equal %i[tenant current_user], trail
      end

      it "answers the first response a provider returns, through its serializer, and runs none after it" do
        expected = [
          401,
          { "content-type" => "application/problem+json" },
          ['{"type":"about:blank","title":"Unauthorized","status":401,"detail":"Sign in first"}']
        ]

        assert_equal [expected, []], [inputs(providers: [unauthorized, traced(:tenant)]).call(requested, {}), trail]
      end

      it "runs before the body is read or anything is coerced, so a caller it turns away learns nothing of them" do
        all = inputs(keyword(:limit, :query, integer), keyword(:body, :body, title), providers: [unauthorized])
        request = env(query: "limit=x", body: "{").merge("skyward.request_id" => "abc-123")
        status, = all.call(request, {})

        assert_equal [401, 0], [status, request["rack.input"].pos]
      end

      it "gets the same request as request:" do
        current_user = provider(:current_user, ->(request) { request })
        request_type = Skyward::API::Boot::REQUEST_TYPE
        passed = inputs(keyword(:request, :request, request_type), providers: [current_user]).call(requested, {}).value

        assert_same passed.fetch(:request), passed.fetch(:current_user)
      end

      it "doesn't pass request: to a method that doesn't take it" do
        assert_equal [:tenant], inputs(providers: [traced(:tenant)]).call(requested, {}).value.keys
      end

      it "lets an exception from its provider through" do
        failing = provider(:current_user, ->(_request) { raise "sessions are down" })
        error = assert_raises(RuntimeError) { inputs(providers: [failing]).call(requested, {}) }

        assert_equal "sessions are down", error.message
      end
    end

    it "lists every problem, in the method's order" do
      all = inputs(keyword(:id, :path, integer), keyword(:limit, :query, integer), keyword(:body, :body, title))
      expected = invalid(
        ["path.id", 'expected Integer, got "x"'],
        ["query.limit", "is required"],
        ["body", "is not valid JSON"]
      )

      assert_equal expected, all.call(env(body: "{"), { id: "x" })
    end

    it "lists no more than MAX_ERRORS problems across keywords" do
      max = Skyward::API::Coercer::MAX_ERRORS
      integers = types::ArrayOf.new(type: integer)
      all = inputs(keyword(:a, :query, integers), keyword(:b, :query, integers))
      query = [*Array.new(max, "a=x"), *Array.new(max, "b=x")].join("&")

      assert_equal max, all.call(env(query:), {}).errors.size
    end
  end
end
