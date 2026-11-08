# frozen_string_literal: true

class Skyward::Request
  # Rack passes these two headers without the HTTP_ prefix the others get.
  UNPREFIXED = { "CONTENT_TYPE" => "content-type", "CONTENT_LENGTH" => "content-length" }.freeze #: Hash[String, String]

  OCTET = "(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])" #: String

  # Rack's trusted proxies: loopback, the private ranges and Unix sockets.
  TRUSTED_PROXY = Regexp.union(
    /\A127(?:\.#{OCTET}){3}\z/,
    /\A::1\z/,
    /\Af[cd][0-9a-f]{2}(?::[0-9a-f]{0,4}){0,7}\z/i,
    /\A10(?:\.#{OCTET}){3}\z/,
    /\A172\.(?:1[6-9]|2[0-9]|3[01])(?:\.#{OCTET}){2}\z/,
    /\A192\.168(?:\.#{OCTET}){2}\z/,
    /\Alocalhost\z|\Aunix(?:\z|:)/i
  ) #: Regexp

  IPV6 = Regexp.union(
    /(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}/,
    /(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?/,
    /(?:[0-9A-Fa-f]{1,4}:){6}\d+\.\d+\.\d+\.\d+/,
    /(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?::(?:[0-9A-Fa-f]{1,4}:)*\d+\.\d+\.\d+\.\d+/,
    /[Ff][Ee]80(?::[0-9A-Fa-f]{1,4}){7}%[-0-9A-Za-z._~]+/,
    /
      [Ff][Ee]80:
      (?:
        (?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?::(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?
        |
        :(?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?
      )?
      :[0-9A-Fa-f]{1,4}%[-0-9A-Za-z._~]+
    /x
  ) #: Regexp

  # Rack's authority grammar: a bracketed IPv6 address or an RFC 3986 host, then an optional port.
  AUTHORITY = /
    \A
    (?:
      \[(?<address>#{IPV6})\]
      |
      (?<address>[-a-zA-Z0-9._~%!$&'()*+,;=]*?)
    )
    (?::\d+)?
    \z
  /x #: Regexp

  # @dynamic env
  attr_reader :env #: Hash[String, untyped]

  # @dynamic headers
  attr_reader :headers #: Hash[String, String]

  # @dynamic cookies
  attr_reader :cookies #: Hash[String, String]

  # @dynamic ip
  attr_reader :ip #: String?

  # @dynamic request_id
  attr_reader :request_id #: String

  # @rbs env: Hash[String, untyped]
  # @rbs return: void
  def initialize(env)
    @env = env
    @headers = read_headers(env)
    @cookies = read_cookies(env["HTTP_COOKIE"])
    @ip = client_ip(addresses(env["REMOTE_ADDR"]), addresses(env["HTTP_X_FORWARDED_FOR"]).map { |entry| bare(entry) })
    @request_id = env.fetch("skyward.request_id")
    freeze
  end

  private

  # @rbs env: Hash[String, untyped]
  # @rbs return: Hash[String, String]
  def read_headers(env)
    env.filter_map do |key, value|
      name = UNPREFIXED[key] || (key.delete_prefix("HTTP_").downcase.tr("_", "-") if key.start_with?("HTTP_"))
      [name, value] if name
    end.to_h.freeze
  end

  # @rbs header: String?
  # @rbs return: Hash[String, String]
  def read_cookies(header)
    # Split as bytes, because String#split raises on a String that isn't valid
    # UTF-8, and a client can send one.
    pairs = header.to_s.b.split(/; */).reject(&:empty?).map do |cookie|
      name, value = cookie.split("=", 2)
      [String.new(name.to_s, encoding: Encoding::UTF_8), Skyward::API::PercentEncoding.decode(value.to_s)]
    end
    # The first of two cookies with one name wins, as in Rack.
    pairs.uniq(&:first).to_h.freeze
  end

  # @rbs header: String?
  # @rbs return: Array[String]
  def addresses(header) = header.to_s.b.split(/[,\s]+/).reject(&:empty?)

  # Rack wraps a bare IPv6 address, which clients send without brackets.
  # @rbs entry: String
  # @rbs return: String?
  def bare(entry)
    wrapped = !entry.start_with?("[") && entry.count(":") > 1 ? "[#{entry}]" : entry
    wrapped[AUTHORITY, :address]
  end

  # As Rack does, a forwarded address is trusted only from a trusted proxy,
  # and the client is the last address that isn't one.
  # @rbs remote: Array[String?]
  # @rbs forwarded: Array[String?]
  # @rbs return: String?
  def client_ip(remote, forwarded)
    (untrusted(remote) || untrusted(forwarded) || [forwarded.first || remote.first]).first
  end

  # @rbs addresses: Array[String?]
  # @rbs return: Array[String?]?
  def untrusted(addresses)
    # An entry that isn't an address is nil, which is never trusted.
    index = addresses.rindex { |address| address.nil? || !TRUSTED_PROXY.match?(address) }
    [addresses.fetch(index)] if index
  end
end
