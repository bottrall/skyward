# frozen_string_literal: true

module Skyward::ORM::Adapters
  extend self

  SCHEMES = {
    "postgres" => PostgreSQL,
    "postgresql" => PostgreSQL,
    "sqlite" => SQLite
  }.freeze #: Hash[String, Skyward::ORM::_Adapter]

  # What comes before "://" is shown only when it's a scheme: in a malformed URL it can hold a password.
  SCHEME = /\A[a-z][a-z0-9+.-]*\z/i #: Regexp

  # @rbs (String url, schemes: Hash[String, Skyward::ORM::_Adapter], requirer: ^(String) -> void)
  #   -> [Skyward::ORM::_Adapter, String]
  def resolve(url, schemes:, requirer:)
    scheme, location = url.split("://", 2)
    adapter = schemes[scheme.to_s] if location
    unless adapter && location
      raise Skyward::Core::BootError,
            unsupported((scheme if location && scheme.to_s.match?(SCHEME)), schemes)
    end

    begin
      # Required only now, so an app's Gemfile names just the one driver it uses.
      requirer.call(adapter.driver)
    rescue LoadError
      raise Skyward::Core::BootError,
            "Skyward ORM needs the #{adapter.driver} gem to connect to a #{scheme}:// URL. " \
            "Add `gem \"#{adapter.driver}\"` to your Gemfile."
    end
    [adapter, location]
  end

  private

  # The URL can hold a password, so only its scheme is shown.
  # @rbs (String? scheme, Hash[String, Skyward::ORM::_Adapter] schemes) -> String
  def unsupported(scheme, schemes)
    url = scheme ? "a #{scheme}:// URL" : "a URL with no scheme"
    suggestion = Skyward::Core::Diagnostics::Suggestion.closest(scheme, schemes.keys) if scheme
    hint = " Did you mean #{suggestion}://?" if suggestion
    "Skyward ORM can't connect to #{url}. It connects to #{schemes.keys.map do |key|
      "#{key}://"
    end.join(", ")} URLs.#{hint}"
  end
end
