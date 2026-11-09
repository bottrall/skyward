# frozen_string_literal: true

module Skyward::ORM::Adapters
  extend self

  SCHEMES = {
    "postgres" => PostgreSQL,
    "postgresql" => PostgreSQL,
    "sqlite" => SQLite
  }.freeze #: Hash[String, Skyward::ORM::_Adapter]

  # @rbs (String url, schemes: Hash[String, Skyward::ORM::_Adapter], requirer: ^(String) -> void)
  #   -> [Skyward::ORM::_Adapter, String]
  def resolve(url, schemes:, requirer:)
    scheme, location = url.split("://", 2)
    adapter = schemes[scheme.to_s] if location
    raise Skyward::Core::BootError, unsupported(location && scheme, schemes) unless adapter && location

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
    "Skyward ORM can't connect to #{url}. It connects to #{schemes.keys.map { |key| "#{key}://" }.join(", ")} URLs."
  end
end
