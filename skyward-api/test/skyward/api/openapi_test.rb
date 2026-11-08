# frozen_string_literal: true

require "json"
require "json_schemer"
require "test_helper"
require "tmpdir"

module OpenAPIFixtures
  Todo = Data.define(:id, :title)
  Draft = Data.define(:title, :note)
  List = Data.define(:todos)

  class Todos < Skyward::API
    description "Things to do."
  end

  class Users < Skyward::API
  end

  Admin = Module.new

  class Admin::Todos < Skyward::API
  end
end

describe Skyward::API::OpenAPI do
  types = Skyward::Types
  integer = types::Scalar.new(name: :integer)
  string = types::Scalar.new(name: :string)
  field = ->(name, type, required = true) { types::Field.new(name:, type:, required:) }
  todo = types::Named.new(
    name: "OpenAPIFixtures::Todo",
    klass: OpenAPIFixtures::Todo,
    fields: [field.call(:id, integer), field.call(:title, string)]
  )
  draft = types::Named.new(
    name: "OpenAPIFixtures::Draft",
    klass: OpenAPIFixtures::Draft,
    fields: [field.call(:title, string), field.call(:note, types::Nullable.new(type: string))]
  )
  list = types::Named.new(
    name: "OpenAPIFixtures::List",
    klass: OpenAPIFixtures::List,
    fields: [field.call(:todos, types::ArrayOf.new(type: draft))]
  )
  request = types::Named.new(name: "Skyward::Request", klass: Skyward::Request, fields: [])
  todo_ref = { "$ref" => "#/components/schemas/OpenAPIFixtures.Todo" }
  problem_ref = { "$ref" => "#/components/schemas/Problem" }

  def keyword(name, source, type, required: true) = Skyward::API::Router::Keyword.new(name:, source:, required:, type:)

  def endpoint(
    to,
    verb: "GET",
    path: ["", "todos"],
    api: OpenAPIFixtures::Todos.new,
    keywords: [],
    returns: [],
    summary: nil,
    description: nil
  )
    written = path.map { |part| part.is_a?(Symbol) ? ":#{part}" : part }.join("/")
    Skyward::API::Router::Endpoint.new(
      verb:,
      pattern: path,
      api:,
      to:,
      label: "#{api.class}##{to} (#{verb} #{written})",
      summary:,
      description:,
      keywords:,
      returns:,
      inputs: Skyward::API::Inputs.new(keywords, max_body_size: 10),
      serializer: Skyward::API::Serializer.new(returns, label: "")
    )
  end

  def json(
    *endpoints,
    static: Skyward::API::Static.new([]),
    title: "API",
    version: "0.1.0",
    description: nil,
    schema_names: {}
  )
    Skyward::API::OpenAPI.json(endpoints, static:, title:, version:, description:, schema_names:)
  end

  def document(*, **) = JSON.parse(json(*, **))

  def refusal(*, **) = assert_raises(Skyward::BootError) { json(*, **) }.message

  def operation(*endpoints, path: "/todos", verb: "get", **) = document(*endpoints, **).dig("paths", path, verb)

  def responses(*, **) = operation(*, **).fetch("responses")

  def returned(type) = responses(endpoint(:index, returns: [type])).dig("200", "content", "application/json", "schema")

  def sent(type, required: true)
    body = endpoint(:create, verb: "POST", keywords: [keyword(:body, :body, type, required:)])
    operation(body, verb: "post").fetch("requestBody")
  end

  def components(*, **) = document(*, **).dig("components", "schemas")

  describe ".json" do
    describe "refusing to boot" do
      it "refuses a route at /openapi.json, where the document is served" do
        assert_equal "OpenAPIFixtures::Todos#docs (POST /openapi.json)\n  " \
                     "With docs: true, /openapi.json serves the OpenAPI document. " \
                     "Change the route's path, or leave out docs:.",
                     refusal(endpoint(:docs, verb: "POST", path: ["", "openapi.json"]))
      end

      it "allows a path parameter where /openapi.json would be" do
        assert_includes document(endpoint(:show, path: ["", :id], keywords: [keyword(:id, :path, string)]))["paths"],
                        "/{id}"
      end

      it "refuses a static file at /openapi.json" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "openapi.json"), "{}")
          static = Skyward::API::Static.new([Skyward::API::Builder::Static.new(prefix: "/", from: root)])

          assert_equal "static serves #{root}/openapi.json at /openapi.json, where docs: true serves the OpenAPI " \
                       "document. Move the file, or leave out docs:.",
                       refusal(endpoint(:index), static:)
        end
      end

      it "refuses two operations with the same ID" do
        assert_equal "OpenAPIFixtures::Todos#index (GET /todos/done)\n  " \
                     "Its OpenAPI operation ID, OpenAPIFixtures.Todos_index, is OpenAPIFixtures::Todos#index " \
                     "(GET /todos)'s too, but each operation needs its own. " \
                     "With docs: true, route each method once, and mount each class once.",
                     refusal(endpoint(:index), endpoint(:index, path: ["", "todos", "done"]))
      end

      it "refuses a schema name OpenAPI doesn't allow" do
        assert_equal "OpenAPIFixtures::Todo's schema name, \"To do\", isn't one OpenAPI allows: use only letters, " \
                     "digits, ., - and _. Name it with Skyward.app(schema_names:).",
                     refusal(endpoint(:index, returns: [todo]), schema_names: { OpenAPIFixtures::Todo => "To do" })
      end

      it "refuses two types with the same schema name" do
        names = { OpenAPIFixtures::Todo => "Thing", OpenAPIFixtures::Draft => "Thing" }

        assert_equal "OpenAPIFixtures::Todo and OpenAPIFixtures::Draft both have the schema name Thing, " \
                     "but each schema needs its own. Name one of them with Skyward.app(schema_names:).",
                     refusal(endpoint(:index, returns: [todo, draft]), schema_names: names)
      end

      it "refuses a type named Problem, which is Skyward API's" do
        assert_match(
          /\ASkyward API's problem\+json and OpenAPIFixtures::Todo both have the schema name Problem/,
          refusal(endpoint(:index, returns: [todo]), schema_names: { OpenAPIFixtures::Todo => "Problem" })
        )
      end
    end

    it "writes the same JSON for the same app" do
      build = -> { json(endpoint(:index, returns: [list, todo]), endpoint(:show, path: ["", "todos", :id])) }

      assert_equal build.call, build.call
    end

    it "is an OpenAPI 3.1 document with the info it's given" do
      written = document(endpoint(:index), title: "Todos", version: "1.0.0", description: "Lists of things.")

      assert_equal(
        ["3.1.0", { "title" => "Todos", "version" => "1.0.0", "description" => "Lists of things." }],
        written.values_at("openapi", "info")
      )
    end

    it "leaves the description out of info when it has none" do
      assert_equal({ "title" => "API", "version" => "0.1.0" }, document(endpoint(:index))["info"])
    end

    it "has a tag for each class, in mount order, with its description when it has one" do
      users = OpenAPIFixtures::Users.new
      written = document(endpoint(:index), endpoint(:index, path: ["", "users"], api: users), endpoint(:show))

      assert_equal [{ "name" => "OpenAPIFixtures.Todos", "description" => "Things to do." },
                    { "name" => "OpenAPIFixtures.Users" }],
                   written["tags"]
    end

    describe "paths" do
      it "writes a path parameter in braces" do
        show = endpoint(:show, path: ["", "todos", :id], keywords: [keyword(:id, :path, integer)])

        assert_equal ["/todos/{id}"], document(show)["paths"].keys
      end

      it "writes the root path as /" do
        assert_equal ["/"], document(endpoint(:index, path: ["", ""]))["paths"].keys
      end

      it "puts each method's operation on a path under its verb, in lowercase" do
        written = document(endpoint(:index), endpoint(:create, verb: "POST"))

        assert_equal %w[get post], written.dig("paths", "/todos").keys
      end
    end

    describe "an operation" do
      it "is tagged with its class and identified by its class and method, with :: as ." do
        written = operation(endpoint(:index, api: OpenAPIFixtures::Admin::Todos.new))

        assert_equal [["OpenAPIFixtures.Admin.Todos"], "OpenAPIFixtures.Admin.Todos_index"],
                     written.values_at("tags", "operationId")
      end

      it "has the route's summary and description" do
        written = operation(endpoint(:index, summary: "List todos.", description: "Newest *first*."))

        assert_equal ["List todos.", "Newest *first*."], written.values_at("summary", "description")
      end

      it "leaves out a summary, a description, parameters and a request body it doesn't have" do
        assert_equal %w[tags operationId responses], operation(endpoint(:index)).keys
      end
    end

    describe "parameters" do
      def parameters(*keywords)
        operation(endpoint(:show, path: ["", "todos", :id], keywords:), path: "/todos/{id}").fetch("parameters")
      end

      it "takes a path parameter as required" do
        assert_equal [{ "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }],
                     parameters(keyword(:id, :path, integer))
      end

      it "leaves null out of a path parameter's schema, and still requires it" do
        assert_equal [{ "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } }],
                     parameters(keyword(:id, :path, types::Nullable.new(type: integer)))
      end

      it "takes a query keyword from the query, required when the method requires it" do
        written = parameters(keyword(:id, :path, integer), keyword(:limit, :query, integer))

        assert_equal(
          { "name" => "limit", "in" => "query", "required" => true, "schema" => { "type" => "integer" } },
          written.last
        )
      end

      it "doesn't require a query keyword the method makes optional" do
        written = parameters(keyword(:id, :path, integer), keyword(:limit, :query, integer, required: false))

        assert_equal [false, { "type" => "integer" }], written.last.values_at("required", "schema")
      end

      it "doesn't require a nullable query keyword, and leaves null out of its schema" do
        written = parameters(keyword(:id, :path, integer), keyword(:done, :query, types::Nullable.new(type: string)))

        assert_equal [false, { "type" => "string" }], written.last.values_at("required", "schema")
      end

      it "leaves out request:, which is no part of the HTTP contract" do
        written = parameters(keyword(:id, :path, integer), keyword(:request, :request, request))

        assert_equal(["id"], written.map { |parameter| parameter["name"] })
      end
    end

    describe "the request body" do
      it "takes body: as a required JSON body of its type" do
        assert_equal(
          { "required" => true, "content" => { "application/json" => { "schema" => todo_ref } } },
          sent(todo)
        )
      end

      it "doesn't require a body the method makes optional" do
        refute sent(todo, required: false).fetch("required")
      end

      it "doesn't require a nullable body, which may be null" do
        written = sent(types::Nullable.new(type: todo))

        assert_equal [false, { "anyOf" => [todo_ref, { "type" => "null" }] }],
                     [written["required"], written.dig("content", "application/json", "schema")]
      end
    end

    describe "responses" do
      def content(type, schema) = { type => { "schema" => schema } }

      it "adds a 422 to an endpoint with inputs, sharing the Problem schema with a returned 422" do
        unprocessable = Skyward::API::Router::Response.new(klass: Skyward::Unprocessable)
        written = responses(endpoint(:index, keywords: [keyword(:limit, :query, integer)], returns: [unprocessable]))

        assert_equal(
          { "description" => "Unprocessable Content", "content" => content("application/problem+json", problem_ref) },
          written["422"]
        )
      end

      it "adds no 422 to an endpoint that takes only request:" do
        written = responses(endpoint(:index, keywords: [keyword(:request, :request, request)]))

        refute_includes written.keys, "422"
      end

      it "adds a 422 to an endpoint that takes request: and a query keyword" do
        written = responses(
          endpoint(:index, keywords: [keyword(:request, :request, request), keyword(:limit, :query, integer)])
        )

        assert_includes written.keys, "422"
      end

      it "adds a 413 and a 415 to an endpoint that takes body:" do
        written = responses(endpoint(:create, verb: "POST", keywords: [keyword(:body, :body, todo)]), verb: "post")

        assert_equal [%w[413 415 422], ["Content Too Large", "Unsupported Media Type"]],
                     [written.keys, written.values_at("413", "415").map { |response| response["description"] }]
      end

      it "orders the responses by status" do
        returns = [
          Skyward::API::Router::Rack.new,
          Skyward::API::Router::Response.new(klass: Skyward::NotFound),
          Skyward::API::Router::Response.new(klass: Skyward::Redirect),
          Skyward::API::Router::Response.new(klass: Skyward::NoContent),
          Skyward::API::Router::Created.new(type: todo),
          todo
        ]

        assert_equal %w[200 201 204 3XX 404 default], responses(endpoint(:index, returns:)).keys
      end

      it "answers Created[T] with a 201 JSON response of T" do
        created = Skyward::API::Router::Created.new(type: todo)

        assert_equal(
          { "201" => { "description" => "Created", "content" => content("application/json", todo_ref) } },
          responses(endpoint(:index, returns: [created]))
        )
      end

      it "answers a problem with its status and the Problem schema as problem+json" do
        not_found = Skyward::API::Router::Response.new(klass: Skyward::NotFound)

        assert_equal(
          { "404" => { "description" => "Not Found", "content" => content("application/problem+json", problem_ref) } },
          responses(endpoint(:index, returns: [not_found]))
        )
      end

      it "answers Redirect with any 3XX status and a location header" do
        redirect = Skyward::API::Router::Response.new(klass: Skyward::Redirect)
        location = { "location" => { "schema" => { "type" => "string" } } }

        assert_equal(
          { "3XX" => { "description" => "Redirect", "headers" => location } },
          responses(endpoint(:index, returns: [redirect]))
        )
      end

      it "answers NoContent with a 204 and no content" do
        no_content = Skyward::API::Router::Response.new(klass: Skyward::NoContent)

        assert_equal({ "204" => { "description" => "No Content" } }, responses(endpoint(:index, returns: [no_content])))
      end

      it "answers a Rack triple with a default response and no schema" do
        description = "A Rack response, whose status and content are known only when it's sent"

        assert_equal(
          { "default" => { "description" => description } },
          responses(endpoint(:index, returns: [Skyward::API::Router::Rack.new]))
        )
      end

      it "answers a plain type with a 200 JSON response" do
        assert_equal(
          { "200" => { "description" => "OK", "content" => content("application/json", todo_ref) } },
          responses(endpoint(:index, returns: [todo]))
        )
      end

      it "gives members that share a status one response, with oneOf their schemas" do
        written = responses(endpoint(:index, returns: [todo, types::Reader::NIL_LITERAL]))

        assert_equal(
          { "oneOf" => [todo_ref, { "type" => "null" }] },
          written.dig("200", "content", "application/json", "schema")
        )
      end
    end

    describe "components" do
      it "has no component for Skyward::Request, which request: takes" do
        written = components(endpoint(:index, keywords: [keyword(:request, :request, request)]))

        assert_equal ["Problem"], written.keys
      end

      it "always has the Problem schema, of RFC 9457 problem+json and a 422's errors" do
        problem = components(endpoint(:index)).fetch("Problem")

        assert_equal [%w[type title status], %w[type title status detail errors]],
                     [problem["required"], problem["properties"].keys]
      end

      it "names a class by its constant path, with :: as ." do
        assert_equal(
          {
            "type" => "object",
            "properties" => { "id" => { "type" => "integer" }, "title" => { "type" => "string" } },
            "required" => %w[id title]
          },
          components(endpoint(:index, returns: [todo])).fetch("OpenAPIFixtures.Todo")
        )
      end

      it "names a class by schema_names: when it's given one, wherever it's referred to" do
        written = document(endpoint(:index, returns: [todo]), schema_names: { OpenAPIFixtures::Todo => "Todo" })

        assert_equal [%w[Problem Todo], { "$ref" => "#/components/schemas/Todo" }],
                     [written.dig("components", "schemas").keys,
                      written.dig(
                        "paths",
                        "/todos",
                        "get",
                        "responses",
                        "200",
                        "content",
                        "application/json",
                        "schema"
                      )]
      end

      it "has each class reached through arrays, records, unions, nullables and other classes, by name" do
        record = types::Record.new(fields: [field.call(:list, types::Nullable.new(type: list))])
        returned = types::Union.new(types: [types::ArrayOf.new(type: record), integer])
        written = components(endpoint(:index, returns: [returned, Skyward::API::Router::Created.new(type: todo)]))

        assert_equal %w[OpenAPIFixtures.Draft OpenAPIFixtures.List OpenAPIFixtures.Todo Problem], written.keys
      end

      it "requires a nullable field of a class used only in responses" do
        assert_equal %w[title note],
                     components(endpoint(:index, returns: [draft])).dig("OpenAPIFixtures.Draft", "required")
      end

      it "doesn't require a nullable field of a class used in a request, even inside another" do
        create = endpoint(:create, verb: "POST", keywords: [keyword(:body, :body, list)], returns: [draft])

        assert_equal ["title"], components(create).dig("OpenAPIFixtures.Draft", "required")
      end
    end

    describe "schemas" do
      it "maps each scalar" do
        written = %i[integer float string bool date time untyped].map do |name|
          returned(types::Scalar.new(name:))
        end

        assert_equal [{ "type" => "integer" }, { "type" => "number" }, { "type" => "string" }, { "type" => "boolean" },
                      { "type" => "string", "format" => "date" }, { "type" => "string", "format" => "date-time" }, {}],
                     written
      end

      it "maps a literal to its value as a const" do
        assert_equal({ "const" => 42 }, returned(types::Literal.new(value: 42)))
      end

      it "maps nil to null" do
        assert_equal({ "type" => "null" }, returned(types::Reader::NIL_LITERAL))
      end

      it "maps an enum to its names" do
        assert_equal({ "type" => "string", "enum" => %w[low high] }, returned(types::Enum.new(symbols: %i[low high])))
      end

      it "makes a nullable type null too, by its type when it has one" do
        nullable = types::Nullable.new(type: types::Scalar.new(name: :date))

        assert_equal({ "type" => %w[string null], "format" => "date" }, returned(nullable))
      end

      it "makes a nullable enum null too, with anyOf" do
        nullable = types::Nullable.new(type: types::Enum.new(symbols: %i[low high]))

        assert_equal(
          { "anyOf" => [{ "type" => "string", "enum" => %w[low high] }, { "type" => "null" }] },
          returned(nullable)
        )
      end

      it "maps an array to its items" do
        assert_equal(
          { "type" => "array", "items" => { "type" => "integer" } },
          returned(types::ArrayOf.new(type: integer))
        )
      end

      it "maps a record to an inline object, requiring the keys it requires" do
        record = types::Record.new(fields: [field.call(:id, integer), field.call(:note, string, false)])

        assert_equal(
          {
            "type" => "object",
            "properties" => { "id" => { "type" => "integer" }, "note" => { "type" => "string" } },
            "required" => ["id"]
          },
          returned(record)
        )
      end

      it "requires a nullable field in a response, which always writes it" do
        record = types::Record.new(fields: [field.call(:note, types::Nullable.new(type: string))])

        assert_equal ["note"], returned(record).fetch("required")
      end

      it "doesn't require a nullable field in a request, which may leave it out" do
        record = types::Record.new(fields: [field.call(:note, types::Nullable.new(type: string))])

        assert_empty sent(record).dig("content", "application/json", "schema", "required")
      end

      it "refers to a class with typed readers by its component" do
        assert_equal todo_ref, returned(todo)
      end

      it "maps a union to oneOf its members" do
        assert_equal(
          { "oneOf" => [{ "type" => "integer" }, todo_ref] },
          returned(types::Union.new(types: [integer, todo]))
        )
      end
    end

    it "is valid against the OpenAPI 3.1 schema" do
      record = types::Record.new(fields: [field.call(:note, types::Nullable.new(type: string), false)])
      endpoints = [
        endpoint(
          :index,
          keywords: [keyword(:tags, :query, types::ArrayOf.new(type: string), required: false)],
          returns: [types::ArrayOf.new(type: todo), record],
          summary: "List todos."
        ),
        endpoint(
          :create,
          verb: "POST",
          keywords: [keyword(:body, :body, list)],
          returns: [Skyward::API::Router::Created.new(type: draft),
                    Skyward::API::Router::Response.new(klass: Skyward::Conflict)]
        ),
        endpoint(
          :show,
          path: ["", "todos", :id],
          keywords: [keyword(:id, :path, integer)],
          returns: [types::Union.new(types: [todo, types::Enum.new(symbols: %i[gone])]),
                    Skyward::API::Router::Response.new(klass: Skyward::Redirect),
                    Skyward::API::Router::Rack.new]
        )
      ]
      errors = JSONSchemer.openapi(document(*endpoints, description: "Todos.")).validate.map { |error| error["error"] }

      assert_empty errors
    end
  end
end
