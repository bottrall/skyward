# frozen_string_literal: true

require "test_helper"

describe Skyward::API::RequestId do
  let(:app) do
    endpoint = lambda do |env|
      [201, { "content-type" => "text/plain", "x-request-id" => "the endpoint's" }, [env.fetch("skyward.request_id")]]
    end
    Skyward::API::RequestId.new(endpoint, generate: -> { "generated" })
  end

  def request(id)
    app.call({ "HTTP_X_REQUEST_ID" => id }.compact)
  end

  def response(id) = [201, { "content-type" => "text/plain", "x-request-id" => id }, [id]]

  it "is frozen" do
    assert_predicate app, :frozen?
  end

  describe "#call" do
    it "passes an incoming ID to the app in the env and replaces the app's x-request-id with it" do
      assert_equal response("abc-123"), request("abc-123")
    end

    it "uses an ID of 200 visible ASCII characters" do
      id = "!~" * 100

      assert_equal response(id), request(id)
    end

    it "generates an ID when none arrives" do
      assert_equal response("generated"), request(nil)
    end

    it "replaces an empty ID" do
      assert_equal response("generated"), request("")
    end

    it "replaces an ID longer than 200 characters" do
      assert_equal response("generated"), request("a" * 201)
    end

    it "replaces an ID with a space" do
      assert_equal response("generated"), request("abc 123")
    end

    it "replaces an ID with a control character" do
      assert_equal response("generated"), request("abc\r\nx-forged: 1")
    end

    it "replaces an ID that isn't ASCII" do
      assert_equal response("generated"), request("café")
    end

    it "replaces an ID that isn't valid UTF-8" do
      assert_equal response("generated"), request((+"abc\xFF").force_encoding(Encoding::UTF_8))
    end
  end
end
