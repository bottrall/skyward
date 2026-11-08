# frozen_string_literal: true

require "cgi/escape"

module Skyward::API::Docs
  extend self

  PATH = "/docs" #: String

  HTML_TYPE = "text/html; charset=utf-8" #: String

  SCALAR_URL = "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.75.1/dist/browser/standalone.js" #: String

  # Recompute from the file whenever SCALAR_URL's version changes.
  SCALAR_INTEGRITY = "sha384-G+2Q2i9l3PPfmYkk0b4BAIUrs7xb/DNaTL1wCYYab4c9dIKlCyiqzC0Qx3eq9Wf6" #: String

  # @rbs title: String
  # @rbs scalar_url: String
  # @rbs return: String
  def page(title:, scalar_url:)
    integrity = %( integrity="#{SCALAR_INTEGRITY}" crossorigin="anonymous") if scalar_url == SCALAR_URL
    # The document's URL is relative, so it's found beside /docs under whatever
    # prefix a larger Rack app mounts this one at.
    <<~HTML.freeze
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{CGI.escapeHTML(title)}</title>
        </head>
        <body>
          <script id="api-reference" data-url="openapi.json" data-configuration='{"withDefaultFonts":false}'></script>
          <script src="#{CGI.escapeHTML(scalar_url)}"#{integrity}></script>
        </body>
      </html>
    HTML
  end
end
