# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Responses do
  let(:api) { Class.new(Skyward::API).new }
  let(:headers) { { "location" => "/todos/1" } }

  def fields(value, *names) = [value.class, *names.map { |name| value.public_send(name) }, value.frozen?]

  it "keeps the helpers private, so a route can't name one" do
    assert_empty Skyward::API.public_instance_methods & %i[created no_content not_found conflict unprocessable]
  end

  it "#created wraps a value in a frozen Created" do
    assert_equal [Skyward::Created, :todo, headers, true], fields(api.send(:created, :todo, headers:), :value, :headers)
  end

  it "#no_content makes a frozen NoContent" do
    assert_equal [Skyward::NoContent, {}, true], fields(api.send(:no_content), :headers)
  end

  it "#not_found makes a frozen NotFound, with no detail unless it's given" do
    found = [api.send(:not_found), api.send(:not_found, "Todo 42 does not exist", headers:)]

    assert_equal(
      [[Skyward::NotFound, nil, {}, true], [Skyward::NotFound, "Todo 42 does not exist", headers, true]],
      found.map { |value| fields(value, :detail, :headers) }
    )
  end

  it "#conflict makes a frozen Conflict" do
    assert_equal [Skyward::Conflict, "Taken", headers, true],
                 fields(api.send(:conflict, "Taken", headers:), :detail, :headers)
  end

  it "#unprocessable makes a frozen Unprocessable" do
    assert_equal [Skyward::Unprocessable, "Bad", {}, true], fields(api.send(:unprocessable, "Bad"), :detail, :headers)
  end
end
