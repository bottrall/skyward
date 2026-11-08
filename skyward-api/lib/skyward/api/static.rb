# frozen_string_literal: true

require "time"

class Skyward::API::Static
  TYPES = {
    ".avif" => "image/avif",
    ".css" => "text/css",
    ".csv" => "text/csv",
    ".gif" => "image/gif",
    ".htm" => "text/html",
    ".html" => "text/html",
    ".ico" => "image/vnd.microsoft.icon",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".js" => "text/javascript",
    ".json" => "application/json",
    ".map" => "application/json",
    ".mjs" => "text/javascript",
    ".pdf" => "application/pdf",
    ".png" => "image/png",
    ".svg" => "image/svg+xml",
    ".txt" => "text/plain",
    ".wasm" => "application/wasm",
    ".webmanifest" => "application/manifest+json",
    ".webp" => "image/webp",
    ".woff" => "font/woff",
    ".woff2" => "font/woff2",
    ".xml" => "application/xml"
  }.freeze #: Hash[String, String]

  # @rbs @statics: Array[Skyward::API::Builder::Static]

  # @rbs statics: Array[Skyward::API::Builder::Static]
  # @rbs return: void
  def initialize(statics)
    @statics = statics.map { |static| static.with(prefix: static.prefix.delete_suffix("/")) }
  end

  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::App::response?
  def call(env)
    return unless %w[GET HEAD].include?(env["REQUEST_METHOD"])

    file = file(env["PATH_INFO"])
    serve(file, env) if file
  end

  # @rbs path: String
  # @rbs return: String?
  def file(path) = @statics.lazy.filter_map { |static| find(static, path) }.first

  private

  # @rbs static: Skyward::API::Builder::Static
  # @rbs path: String
  # @rbs return: String?
  def find(static, path)
    return unless path == static.prefix || path.start_with?("#{static.prefix}/")

    rest = path.delete_prefix(static.prefix)
    rest = "#{rest}index.html" if rest.empty? || rest.end_with?("/")
    names = rest.split("/").map { |segment| Skyward::API::PercentEncoding.decode(segment) }
    # Each segment is decoded after splitting, so an escaped / stays inside a
    # name, where joining would make it a separator. File raises on a NUL.
    return if names.any? { |name| name == ".." || name.include?("/") || name.include?("\0") }

    # File.file? follows a symlink under from: whoever deployed it put it there.
    file = File.join(static.from, *names)
    file if File.file?(file)
  end

  # @rbs file: String
  # @rbs env: Hash[String, untyped]
  # @rbs return: Skyward::API::App::response
  def serve(file, env)
    stat = File.stat(file)
    etag = etag(stat)
    validators = { "last-modified" => stat.mtime.httpdate, "etag" => etag, "cache-control" => "no-cache" }
    return [304, validators, []] if fresh?(env, etag, stat.mtime)

    type = TYPES.fetch(File.extname(file).downcase(:ascii), "application/octet-stream")
    headers = { "content-type" => type, "content-length" => stat.size.to_s, **validators }
    [200, headers, [File.binread(file)]]
  end

  # @rbs stat: File::Stat
  # @rbs return: String
  def etag(stat)
    nanoseconds = (stat.mtime.to_i * 1_000_000_000) + stat.mtime.nsec
    %("#{nanoseconds.to_s(16)}-#{stat.size.to_s(16)}")
  end

  # If-Modified-Since only counts without If-None-Match (RFC 9110, 13.2.2),
  # and to the second, the precision of last-modified.
  # @rbs env: Hash[String, untyped]
  # @rbs etag: String
  # @rbs modified: Time
  # @rbs return: bool
  def fresh?(env, etag, modified)
    tags = env["HTTP_IF_NONE_MATCH"]
    return tags.b.split(",").any? { |tag| ["*", etag].include?(tag.strip.delete_prefix("W/")) } if tags

    since = http_date(env["HTTP_IF_MODIFIED_SINCE"])
    since ? since.to_i >= modified.to_i : false
  end

  # @rbs value: String?
  # @rbs return: Time?
  def http_date(value)
    Time.httpdate(value) if value
  rescue ArgumentError
    nil
  end
end
