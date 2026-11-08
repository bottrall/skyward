# frozen_string_literal: true

require "test_helper"

module RoutesFixtures
  class Todos < Skyward::API
  end

  class Health < Skyward::API
  end
end

describe Skyward::API::Routes do
  describe ".table" do
    def endpoint(verb, pattern, to, signature, api: RoutesFixtures::Todos.new)
      Skyward::API::Router::Endpoint.new(
        verb:,
        pattern:,
        api:,
        to:,
        label: "",
        summary: nil,
        description: nil,
        keywords: [],
        providers: [],
        returns: [],
        signature:,
        inputs: Skyward::API::Inputs.new([], providers: [], max_body_size: 10),
        serializer: Skyward::API::Serializer.new([], label: "")
      )
    end

    it "prints nothing for no endpoints" do
      assert_equal "", Skyward::API::Routes.table([])
    end

    it "prints a line per endpoint, in order, with each column as wide as its widest entry and then two spaces" do
      endpoints = [
        endpoint("GET", ["", "todos"], :index, "() -> Array[Todo]"),
        endpoint("DELETE", ["", "todos", :id], :destroy, "(id: Integer) -> (NoContent | NotFound)"),
        endpoint("GET", ["", ""], :check, "() -> untyped", api: RoutesFixtures::Health.new)
      ]

      assert_equal <<~TEXT, Skyward::API::Routes.table(endpoints)
        GET     /todos      RoutesFixtures::Todos#index    () -> Array[Todo]
        DELETE  /todos/:id  RoutesFixtures::Todos#destroy  (id: Integer) -> (NoContent | NotFound)
        GET     /           RoutesFixtures::Health#check   () -> untyped
      TEXT
    end

    it "puts a signature wrapped over several lines on one" do
      wrapped = endpoint("DELETE", ["", "todos", :id], :destroy, "(id: Integer)\n             -> (Todo | :gone)?")

      assert_equal "DELETE  /todos/:id  RoutesFixtures::Todos#destroy  (id: Integer) -> (Todo | :gone)?\n",
                   Skyward::API::Routes.table([wrapped])
    end
  end
end
