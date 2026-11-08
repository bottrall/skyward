# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Application do
  let(:endpoints) { [] }
  let(:built) { [] }
  let(:application) do
    Skyward::API::Application.new(
      ->(env) { [200, {}, [env["PATH_INFO"]]] },
      endpoints:,
      openapi: lambda do
        built << :openapi
        { openapi: "3.1.0" }
      end
    )
  end

  it "keeps its endpoints" do
    assert_same endpoints, application.endpoints
  end

  it "is frozen" do
    assert_predicate application, :frozen?
  end

  it "answers a request with the app it wraps" do
    assert_equal [200, {}, ["/todos"]], application.call({ "PATH_INFO" => "/todos" })
  end

  it "builds its OpenAPI document only when asked" do
    application
    untouched = built.dup

    assert_equal [[], { openapi: "3.1.0" }, [:openapi]], [untouched, application.openapi, built]
  end
end
