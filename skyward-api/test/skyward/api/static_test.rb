# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::API::Static do
  let(:root) { Dir.mktmpdir }
  let(:public_dir) { File.join(root, "public") }
  let(:static) { files(["/assets", public_dir]) }
  let(:modified) { Time.at(1_700_000_000, 123_456_789, :nsec) }
  let(:last_modified) { "Tue, 14 Nov 2023 22:13:20 GMT" }

  before do
    write "public/style.css", "body {}"
    write "public/index.html", "<h1>Home</h1>"
    write "public/docs/index.html", "<h1>Docs</h1>"
    write "secret.txt", "hunter2"
  end

  after { FileUtils.remove_entry(root) }

  def files(*statics)
    Skyward::API::Static.new(statics.map { |prefix, from| Skyward::API::Builder::Static.new(prefix:, from:) })
  end

  def write(path, content)
    file = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
    File.utime(modified, modified, file)
  end

  def request(path, headers = {}, method: "GET", server: static)
    server.call({ "REQUEST_METHOD" => method, "PATH_INFO" => path, **headers })
  end

  def body(path, **)
    request(path, **)&.last&.first
  end

  def status(path, headers = {})
    request(path, headers)&.first
  end

  # The modification time in nanoseconds, then the size, both in hex.
  def etag(size = 7) = %("17979cfe3d85cd15-#{size.to_s(16)}")

  def validators(size)
    { "last-modified" => last_modified, "etag" => etag(size), "cache-control" => "no-cache" }
  end

  def served(type, content)
    size = content.bytesize
    [200, { "content-type" => type, "content-length" => size.to_s, **validators(size) }, [content]]
  end

  describe ".new" do
    it "drops a trailing slash from the prefix" do
      assert_equal "body {}", body("/assets/style.css", server: files(["/assets/", public_dir]))
    end

    it "serves every path from a static at /" do
      assert_equal "body {}", body("/style.css", server: files(["/", public_dir]))
    end
  end

  describe "#call" do
    it "serves a file under the prefix with its type, size, modification time, ETag and no-cache" do
      assert_equal served("text/css", "body {}"), request("/assets/style.css")
    end

    it "answers nothing to a method other than GET or HEAD" do
      assert_nil request("/assets/style.css", method: "POST")
    end

    it "answers HEAD like GET, leaving the app to drop the body" do
      assert_equal served("text/css", "body {}"), request("/assets/style.css", method: "HEAD")
    end

    it "tries each static in order, and the first that has the file answers" do
      write "other/style.css", "p {}"
      server = files(["/assets", File.join(root, "other")], ["/assets", public_dir])

      assert_equal "p {}", body("/assets/style.css", server:)
    end

    it "falls through to the next static when one doesn't have the file" do
      server = files(["/assets", File.join(root, "other")], ["/assets", public_dir])

      assert_equal "body {}", body("/assets/style.css", server:)
    end

    it "answers nothing outside the prefix" do
      assert_nil request("/style.css")
    end

    it "answers nothing for a path that only starts with the prefix" do
      write "public/-old/style.css", "p {}"

      assert_nil request("/assets-old/style.css")
    end

    it "serves index.html for the prefix itself" do
      assert_equal "<h1>Home</h1>", body("/assets")
    end

    it "serves a directory's index.html for a path ending in /" do
      assert_equal "<h1>Docs</h1>", body("/assets/docs/")
    end

    it "percent-decodes the path" do
      write "public/hello world.txt", "Hello"

      assert_equal "Hello", body("/assets/hello%20world.txt")
    end

    it "answers nothing for a .. segment" do
      assert_nil request("/assets/../secret.txt")
    end

    it "answers nothing for an escaped .. segment, in either case" do
      responses = ["/assets/%2e%2e/secret.txt", "/assets/%2E%2E/secret.txt"].map { |path| request(path) }

      assert_equal [nil, nil], responses
    end

    it "answers nothing for an escaped slash" do
      assert_nil request("/assets/..%2fsecret.txt")
    end

    it "answers nothing for an escaped NUL" do
      assert_nil request("/assets/style.css%00")
    end

    it "answers nothing for a missing file" do
      assert_nil request("/assets/missing.css")
    end

    it "answers nothing for a directory without a trailing slash" do
      assert_nil request("/assets/docs")
    end

    it "answers 304 with the validators and no body when If-None-Match has the ETag" do
      assert_equal [304, validators(7), []], request("/assets/style.css", { "HTTP_IF_NONE_MATCH" => etag })
    end

    it "types a file by its extension, in any case" do
      write "public/LOGO.PNG", "png"

      assert_equal served("image/png", "png"), request("/assets/LOGO.PNG")
    end

    it "types a file with an unknown extension as application/octet-stream" do
      write "public/data.bin", "bin"

      assert_equal served("application/octet-stream", "bin"), request("/assets/data.bin")
    end

    it "matches a weak ETag in If-None-Match" do
      assert_equal 304, status("/assets/style.css", { "HTTP_IF_NONE_MATCH" => "W/#{etag}" })
    end

    it "matches an ETag in a list in If-None-Match" do
      assert_equal 304, status("/assets/style.css", { "HTTP_IF_NONE_MATCH" => %("other", #{etag}) })
    end

    it "matches * in If-None-Match" do
      assert_equal 304, status("/assets/style.css", { "HTTP_IF_NONE_MATCH" => "*" })
    end

    it "matches If-None-Match by its bytes, whatever its encoding" do
      tags = "\xFF, #{etag}".force_encoding(Encoding::UTF_8)

      assert_equal 304, status("/assets/style.css", { "HTTP_IF_NONE_MATCH" => tags })
    end

    it "serves the file when If-None-Match has only other ETags" do
      assert_equal 200, status("/assets/style.css", { "HTTP_IF_NONE_MATCH" => %("other") })
    end

    it "ignores If-Modified-Since when If-None-Match is sent" do
      headers = { "HTTP_IF_NONE_MATCH" => %("other"), "HTTP_IF_MODIFIED_SINCE" => last_modified }

      assert_equal 200, status("/assets/style.css", headers)
    end

    it "answers 304 when If-Modified-Since is the modification time, to the second" do
      assert_equal 304, status("/assets/style.css", { "HTTP_IF_MODIFIED_SINCE" => last_modified })
    end

    it "serves the file when If-Modified-Since is earlier" do
      assert_equal 200, status("/assets/style.css", { "HTTP_IF_MODIFIED_SINCE" => "Tue, 14 Nov 2023 22:13:19 GMT" })
    end

    it "serves the file when If-Modified-Since isn't an HTTP date" do
      assert_equal 200, status("/assets/style.css", { "HTTP_IF_MODIFIED_SINCE" => "yesterday" })
    end
  end
end
