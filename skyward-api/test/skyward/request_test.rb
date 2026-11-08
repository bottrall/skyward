# frozen_string_literal: true

require "test_helper"

describe Skyward::Request do
  def request(env = {}) = Skyward::Request.new({ "skyward.request_id" => "abc-123", **env })

  it "is frozen" do
    assert_predicate request, :frozen?
  end

  it "keeps the raw Rack env" do
    env = { "skyward.request_id" => "abc-123", "rack.input" => :input }

    assert_same env, Skyward::Request.new(env).env
  end

  describe "#headers" do
    it "names each HTTP_ header in lowercase with dashes, content-type and content-length among them" do
      headers = request(
        "HTTP_AUTHORIZATION" => "Bearer abc",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.7",
        "CONTENT_TYPE" => "application/json",
        "CONTENT_LENGTH" => "2",
        "REQUEST_METHOD" => "GET"
      ).headers
      expected = {
        "authorization" => "Bearer abc",
        "x-forwarded-for" => "203.0.113.7",
        "content-type" => "application/json",
        "content-length" => "2"
      }

      assert_equal [expected, true], [headers, headers.frozen?]
    end
  end

  describe "#cookies" do
    def cookies(header) = request("HTTP_COOKIE" => header).cookies

    it "reads each cookie from the cookie header, frozen" do
      cookies = cookies("session=abc; theme=dark")

      assert_equal [{ "session" => "abc", "theme" => "dark" }, true], [cookies, cookies.frozen?]
    end

    it "is empty without a cookie header" do
      assert_equal({}, request.cookies)
    end

    it "percent-decodes a value, but keeps a +" do
      assert_equal({ "token" => "a b+c=" }, cookies("token=a%20b+c="))
    end

    it "keeps the first of two cookies with one name" do
      assert_equal({ "session" => "first" }, cookies("session=first; session=second"))
    end

    it "skips empty pairs, and reads a cookie without = as an empty value" do
      assert_equal({ "flag" => "", "theme" => "dark" }, cookies("flag;; theme=dark"))
    end

    it "reads a header that isn't valid UTF-8" do
      assert_equal "abc", cookies((+"bad=\xFF; session=abc").force_encoding(Encoding::UTF_8))["session"]
    end
  end

  describe "#ip" do
    def ip(remote, forwarded = nil)
      request({ "REMOTE_ADDR" => remote, "HTTP_X_FORWARDED_FOR" => forwarded }.compact).ip
    end

    it "is the remote address when it isn't a trusted proxy, whatever X-Forwarded-For says" do
      assert_equal "203.0.113.7", ip("203.0.113.7", "198.51.100.1")
    end

    it "is the last forwarded address that isn't a trusted proxy, from a trusted proxy" do
      assert_equal "198.51.100.2", ip("10.0.0.1", "198.51.100.1, 198.51.100.2,192.168.1.1 172.16.0.1")
    end

    it "trusts each of Rack's trusted proxies" do
      proxies = %w[127.0.0.1 ::1 fd12:3456::1 10.1.2.3 172.31.255.255 192.168.0.1 localhost unix unix:/tmp/puma.sock]

      assert_equal(Array.new(proxies.size, "198.51.100.1"), proxies.map { |proxy| ip(proxy, "198.51.100.1") })
    end

    it "doesn't trust a public address that looks like a private one" do
      assert_equal %w[172.32.0.1 10.0.0.256], [ip("172.32.0.1", "198.51.100.1"), ip("10.0.0.256", "198.51.100.1")]
    end

    it "is the first forwarded address when every one is a trusted proxy" do
      assert_equal "10.0.0.2", ip("10.0.0.1", "10.0.0.2, 10.0.0.3")
    end

    it "is the remote address when every address is a trusted proxy and nothing is forwarded" do
      assert_equal "10.0.0.1", ip("10.0.0.1")
    end

    it "takes X-Forwarded-For when there's no remote address" do
      assert_equal "198.51.100.1", ip(nil, "198.51.100.1")
    end

    it "is nil without a remote address or X-Forwarded-For" do
      assert_nil request.ip
    end

    it "drops the port from a forwarded address" do
      forwarded = ["198.51.100.1:5555", "[2001:db8::1]:443"]

      assert_equal(%w[198.51.100.1 2001:db8::1], forwarded.map { |entry| ip("10.0.0.1", entry) })
    end

    it "reads a bare or bracketed IPv6 forwarded address" do
      assert_equal %w[2001:db8::1 2001:db8::1], [ip("10.0.0.1", "2001:db8::1"), ip("10.0.0.1", "[2001:db8::1]")]
    end

    it "trusts a proxy whatever its port" do
      assert_equal "198.51.100.1", ip("10.0.0.1", "198.51.100.1, 10.0.0.2:8080")
    end

    it "is nil when the last untrusted forwarded entry isn't an address" do
      assert_nil ip("10.0.0.1", "198.51.100.1, <script>, 192.168.1.5")
    end

    it "reads an X-Forwarded-For that isn't valid UTF-8" do
      assert_equal "198.51.100.1", ip("10.0.0.1", (+"\xFF, 198.51.100.1, 10.0.0.2").force_encoding(Encoding::UTF_8))
    end
  end

  it "has the request ID" do
    assert_equal "abc-123", request.request_id
  end
end
