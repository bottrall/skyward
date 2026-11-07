# frozen_string_literal: true

require "test_helper"
require "tmpdir"

describe Skyward::API::App do
  let(:root) { Dir.mktmpdir }
  let(:todos) do
    Class.new(Skyward::API) do
      get "/:id", to: :show
      get "/:id/fail", to: :fail

      def show(id:) = { id:, title: "Ship it" }

      def fail(id:) = raise("todo #{id} is secret")
    end.new
  end
  let(:app) do
    router = Skyward::API::Router.new([Skyward::API::Builder::Mount.new(api: todos, at: "/todos")])
    static = Skyward::API::Static.new([Skyward::API::Builder::Static.new(prefix: "/", from: File.join(root, "public"))])
    Skyward::API::App.new(router, static)
  end

  before do
    FileUtils.mkdir_p(File.join(root, "public/todos"))
    File.write(File.join(root, "public/todos/42"), "A static todo")
    File.write(File.join(root, "public/hello.txt"), "Hello")
    File.write(File.join(root, "secret.txt"), "hunter2")
  end

  after { FileUtils.remove_entry(root) }

  def request(method, path)
    app.call({ "REQUEST_METHOD" => method, "PATH_INFO" => path })
  end

  def problem(status, title)
    body = %({"type":"about:blank","title":"#{title}","status":#{status}})
    [status, { "content-type" => "application/problem+json" }, [body]]
  end

  it "is frozen" do
    assert_predicate app, :frozen?
  end

  describe "#call" do
    it "calls the matched method with the path parameters and answers with its return value as JSON" do
      expected = [200, { "content-type" => "application/json" }, ['{"id":"42","title":"Ship it"}']]

      assert_equal expected, request("GET", "/todos/42")
    end

    it "answers an exception from the method with a 500 problem that doesn't reveal it" do
      assert_equal problem(500, "Internal Server Error"), request("GET", "/todos/42/fail")
    end

    it "serves a static file when no route matches" do
      assert_equal ["Hello"], request("GET", "/hello.txt").last
    end

    it "lets a route take precedence over a static file" do
      assert_equal ['{"id":"42","title":"Ship it"}'], request("GET", "/todos/42").last
    end

    it "answers a request no route or file matches with a 404 problem" do
      assert_equal problem(404, "Not Found"), request("GET", "/todos")
    end

    it "answers a path that climbs out of a static directory with a 404 problem" do
      responses = ["/../secret.txt", "/%2e%2e/secret.txt"].map { |path| request("GET", path) }

      assert_equal [problem(404, "Not Found")] * 2, responses
    end
  end
end
