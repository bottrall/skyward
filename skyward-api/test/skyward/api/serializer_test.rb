# frozen_string_literal: true

require "test_helper"

describe Skyward::API::Serializer do
  types = Skyward::Types
  router = Skyward::API::Router
  untyped = types::Scalar.new(name: :untyped)
  todo = types::Record.new(
    fields: [types::Field.new(name: :title, type: types::Scalar.new(name: :string), required: true)]
  )
  not_found = router::Response.new(klass: Skyward::NotFound)

  json = { "content-type" => "application/json" }
  problem_json = { "content-type" => "application/problem+json" }

  define_method(:serializer) { |*returns| Skyward::API::Serializer.new(returns, label: "TodosAPI#show (GET /todos/:id)") }

  define_method(:failure) do |returns, value|
    assert_raises(Skyward::API::ReturnTypeError) { serializer(*returns).call(value) }.message
  end

  it "is frozen" do
    assert_predicate serializer(todo), :frozen?
  end

  describe "#call" do
    describe "a Created" do
      let(:created) { Skyward::Created.new(value: { title: "Ship it", secret: "x" }, headers: { "location" => "/todos/1" }) }

      it "answers with a 201, its headers, and its value as its type writes it" do
        expected = [201, { **json, "location" => "/todos/1" }, ['{"title":"Ship it"}']]

        assert_equal expected, serializer(router::Created.new(type: todo)).call(created)
      end

      it "raises naming where its value doesn't fit" do
        message = failure([router::Created.new(type: todo)], Skyward::Created.new(value: { title: nil }, headers: {}))

        assert_equal "TodosAPI#show (GET /todos/:id) returned nil at value.title, which isn't String, " \
                     "in its return type Skyward::Created[{ title: String }]",
                     message
      end

      it "writes a value with a later Created whose value's type fits it" do
        value = Skyward::Created.new(value: ["a"], headers: {})
        returns = [router::Created.new(type: types::ArrayOf.new(type: types::Scalar.new(name: :integer))),
                   router::Created.new(type: types::ArrayOf.new(type: types::Scalar.new(name: :string)))]

        assert_equal [201, json, ['["a"]']], serializer(*returns).call(value)
      end
    end

    it "answers a NoContent with a 204, a copy of its headers, and no body" do
      headers = { "x-done" => "yes" }.freeze
      status, answered, body = serializer(router::Response.new(klass: Skyward::NoContent)).call(Skyward::NoContent.new(headers:))

      assert_equal [204, headers, [], false], [status, answered, body, answered.frozen?]
    end

    describe "a problem" do
      it "answers with its status, problem+json and its headers, and a body with its detail" do
        value = Skyward::NotFound.new(detail: "Todo 42 does not exist", headers: { "x-hint" => "search" })
        body = '{"type":"about:blank","title":"Not Found","status":404,"detail":"Todo 42 does not exist"}'

        assert_equal [404, { **problem_json, "x-hint" => "search" }, [body]], serializer(not_found).call(value)
      end

      it "leaves detail out when it isn't given" do
        body = '{"type":"about:blank","title":"Not Found","status":404}'

        assert_equal [body], serializer(not_found).call(Skyward::NotFound.new(detail: nil, headers: {})).last
      end

      it "answers each other problem with its own status and title" do
        classes = [Skyward::BadRequest, Skyward::Unauthorized, Skyward::Forbidden, Skyward::Conflict, Skyward::Unprocessable]
        responses = classes.map do |klass|
          serializer(router::Response.new(klass:)).call(klass.new(detail: "Taken", headers: {}))
        end

        assert_equal(
          [[400, "Bad Request"], [401, "Unauthorized"], [403, "Forbidden"], [409, "Conflict"],
           [422, "Unprocessable Content"]],
          responses.map { |status, _, body| [status, JSON.parse(body.first).fetch("title")] }
        )
      end
    end

    it "answers a Redirect with its status, a location header and its headers, and no body" do
      value = Skyward::Redirect.new(to: "/todos/1", status: 307, headers: { "x-moved" => "yes" })

      assert_equal [307, { "location" => "/todos/1", "x-moved" => "yes" }, []],
                   serializer(router::Response.new(klass: Skyward::Redirect)).call(value)
    end

    describe "an untyped return" do
      it "answers each response value as itself" do
        statuses = [
          Skyward::Created.new(value: {}, headers: {}),
          Skyward::NoContent.new(headers: {}),
          Skyward::BadRequest.new(detail: "Bad", headers: {}),
          Skyward::Unauthorized.new(detail: "Sign in first", headers: {}),
          Skyward::Forbidden.new(detail: "Not yours", headers: {}),
          Skyward::NotFound.new(detail: nil, headers: {}),
          Skyward::Conflict.new(detail: "Taken", headers: {}),
          Skyward::Unprocessable.new(detail: "Bad", headers: {}),
          Skyward::Redirect.new(to: "/", status: 302, headers: {})
        ].map { |value| serializer(untyped).call(value).first }

        assert_equal [201, 204, 400, 401, 403, 404, 409, 422, 302], statuses
      end

      it "answers a Created's value as untyped" do
        created = Skyward::Created.new(value: { tags: [:low] }, headers: {})

        assert_equal [201, json, ['{"tags":["low"]}']], serializer(untyped).call(created)
      end

      it "answers anything else with a 200, as untyped" do
        assert_equal [200, json, ['{"done":true}']], serializer(untyped).call({ done: true })
      end

      it "raises for a value untyped can't write, naming it" do
        assert_equal "TodosAPI#show (GET /todos/:id) returned Object, which isn't something with to_h",
                     failure([untyped], Object.new)
      end
    end

    it "answers a value of a type with a 200 and the value as that type writes it" do
      assert_equal [200, json, ['{"title":"Ship it"}']], serializer(todo).call({ title: "Ship it", secret: "x" })
    end

    it "answers nil with a 200 and null where the return type is nullable" do
      assert_equal [200, json, ["null"]], serializer(todo, types::Reader::NIL_LITERAL).call(nil)
    end

    it "writes a value with the first member it fits" do
      response = serializer(
        router::Created.new(type: todo),
        not_found,
        todo
      ).call(Skyward::NotFound.new(detail: nil, headers: {}))

      assert_equal 404, response.first
    end

    it "raises for a value no member fits, naming the endpoint, the return type and the value's class" do
      assert_equal "TodosAPI#show (GET /todos/:id) returned Skyward::Conflict, which isn't { title: String } | Skyward::NotFound",
                   failure([todo, not_found], Skyward::Conflict.new(detail: "Taken", headers: {}))
    end

    it "raises for a field that doesn't fit, naming where it is" do
      assert_equal "TodosAPI#show (GET /todos/:id) returned 42 at title, which isn't String, " \
                   "in its return type { title: String } | Skyward::NotFound",
                   failure([todo, not_found], { title: 42 })
    end
  end
end
