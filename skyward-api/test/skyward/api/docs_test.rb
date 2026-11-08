# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Docs do
  describe ".page" do
    def page(title: "API", scalar_url: Skyward::API::Docs::SCALAR_URL)
      Skyward::API::Docs.page(title:, scalar_url:)
    end

    def scripts(html) = html.scan(%r{<script\b[^>]*>.*?</script>}m)

    it "is titled with the title, escaped" do
      assert_includes page(title: "<Todos> & more"), "<title>&lt;Todos&gt; &amp; more</title>"
    end

    it "points Scalar at the document by a relative URL, without its default fonts" do
      assert_equal '<script id="api-reference" data-url="openapi.json" ' \
                   "data-configuration='{\"withDefaultFonts\":false}'></script>",
                   scripts(page).first
    end

    it "loads Scalar from jsDelivr at a pinned version by default, checked by its integrity hash" do
      expected = '<script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.75.1/dist/browser/standalone.js" ' \
                 'integrity="sha384-G+2Q2i9l3PPfmYkk0b4BAIUrs7xb/DNaTL1wCYYab4c9dIKlCyiqzC0Qx3eq9Wf6" ' \
                 'crossorigin="anonymous"></script>'

      assert_equal expected, scripts(page).last
    end

    it "loads Scalar from the URL it's given, with no integrity hash" do
      assert_equal '<script src="/scalar.js"></script>', scripts(page(scalar_url: "/scalar.js")).last
    end

    it "escapes the URL it's given" do
      assert_equal '<script src="/scalar.js?a=1&amp;b=&quot;2&quot;"></script>',
                   scripts(page(scalar_url: '/scalar.js?a=1&b="2"')).last
    end

    it "has no inline JavaScript" do
      assert_equal([""] * 2, scripts(page).map { |script| script[%r{>(.*)</script>}m, 1] })
    end

    it "is frozen" do
      assert_predicate page, :frozen?
    end
  end
end
