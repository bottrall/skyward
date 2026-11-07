# frozen_string_literal: true

module Skyward::API::PercentEncoding
  extend self

  ESCAPE = /%\h\h/ #: Regexp

  # Lenient, unlike URI.decode_uri_component, because servers pass the path
  # through undecoded and a malformed escape is the client's to send.
  # @rbs text: String
  # @rbs return: String
  def decode(text)
    text.b.gsub(ESCAPE) { |escape| escape.delete_prefix("%").hex.chr }.force_encoding(Encoding::UTF_8)
  end
end
