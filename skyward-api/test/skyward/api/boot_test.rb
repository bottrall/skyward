# frozen_string_literal: true

require "stringio"
require "test_helper"
require_relative "../../fixtures/boot/boot_fixtures"

describe Skyward::API::Boot do
  types = Skyward::Types
  reader = Skyward::Types::Reader.new(Skyward::Signatures.load(File.expand_path("../../fixtures/boot/sig", __dir__)))

  integer = types::Scalar.new(name: :integer)
  untyped = types::Scalar.new(name: :untyped)
  todo = types::Named.new(
    name: "BootFixtures::Todo",
    klass: BootFixtures::Todo,
    fields: [
      types::Field.new(name: :id, type: integer, required: true),
      types::Field.new(name: :title, type: types::Scalar.new(name: :string), required: true)
    ]
  )

  define_method(:boot) do |*mounts, strict: false|
    Skyward::API::Boot.endpoints(
      mounts.map { |api, at| Skyward::API::Builder::Mount.new(api:, at:) },
      reader:,
      max_body_size: 10,
      strict:
    )
  end

  define_method(:refusal) do |*mounts, strict: false|
    assert_raises(Skyward::BootError) { boot(*mounts, strict:) }.message
  end

  def keyword(name, source, required, type)
    Skyward::API::Router::Keyword.new(name:, source:, required:, type:)
  end

  let(:todos) { BootFixtures::Todos.new }

  def endpoint(endpoints, to, verb = "GET") = endpoints.find { |found| found.to == to && found.verb == verb }

  describe ".endpoints" do
    it "builds an endpoint for each route, in mount order and then declaration order" do
      endpoints = boot([todos, "/todos"], [BootFixtures::NewForm.new, "/forms"])

      assert_equal %i[index index show create destroy new_form], endpoints.map(&:to)
    end

    it "builds an endpoint for each prefix an object is mounted at" do
      form = BootFixtures::NewForm.new

      assert_equal [["", "todos", "new"], ["", "tasks", "new"]], boot([form, "/todos"], [form, "/tasks"]).map(&:pattern)
    end

    it "records the route's verb, the object and the method" do
      show = endpoint(boot([todos, "/todos"]), :show)

      assert_equal ["GET", todos, :show], [show.verb, show.api, show.to]
    end

    it "keeps the route's label, summary and description" do
      show = endpoint(boot([BootFixtures::Documented.new, "/todos"]), :show)

      assert_equal ["BootFixtures::Documented#show (GET /todos/:id)", "Fetch a todo.", "It's *Markdown*."],
                   [show.label, show.summary, show.description]
    end

    it "keeps the method's signature as its signature file writes it" do
      assert_equal "(?done: bool?, ?tags: Array[:low | :high]) -> Array[Todo]",
                   endpoint(boot([todos, "/todos"]), :index).signature
    end

    it "keeps a signature wrapped over several lines as it's wrapped" do
      assert_equal "(id: Integer)\n               -> (Todo | :gone)?",
                   endpoint(boot([todos, "/todos"]), :destroy, "DELETE").signature
    end

    it "writes an untyped endpoint's signature as rbs-inline would, with each keyword and the return untyped" do
      assert_equal "(name: untyped, ?shout: untyped, ?request: untyped) -> untyped",
                   endpoint(boot([BootFixtures::Unsigned.new, "/"]), :greet).signature
    end

    it "writes an untyped endpoint with no keywords as taking none" do
      assert_equal "() -> untyped", endpoint(boot([BootFixtures::UnsignedMethod.new, "/"]), :index).signature
    end

    it "joins the prefix to a route's path with one slash, as a pattern of segments and parameters" do
      assert_equal ["", "todos", :id], endpoint(boot([todos, "/todos"]), :show).pattern
    end

    it "joins the prefix to a root route without a trailing slash" do
      assert_equal ["", "todos"], endpoint(boot([todos, "/todos"]), :index).pattern
    end

    it "drops a trailing slash from the prefix and the route's path" do
      assert_equal ["", "todos", "done"], boot([todos, "/todos/"]).fetch(1).pattern
    end

    it "puts a route mounted at / at its own path" do
      assert_equal ["", :id], endpoint(boot([todos, "/"]), :show).pattern
    end

    it "puts a root route mounted at / at /" do
      assert_equal ["", ""], endpoint(boot([todos, "/"]), :index).pattern
    end

    it "refuses a summary with a line break" do
      assert_equal "BootFixtures::Summarised#index (GET /)\n  " \
                   "Its summary: has a line break, but a summary is one line. Put the rest in description:.",
                   refusal([BootFixtures::Summarised.new, "/"])
    end

    describe "shadowing" do
      it "refuses a route that a route before it in the same class matches every path of" do
        assert_equal "BootFixtures::StaticLast#new_form (GET /new)\n  " \
                     "BootFixtures::StaticLast#show (GET /:id) is tried first and matches every path this route " \
                     "does, so this route is never reached. Declare the static route first.",
                     refusal([BootFixtures::StaticLast.new, "/"])
      end

      it "refuses a route that a route in an earlier mount matches every path of" do
        assert_equal "BootFixtures::NewForm#new_form (GET /todos/new)\n  " \
                     "BootFixtures::Todos#show (GET /todos/:id) is tried first and matches every path this route " \
                     "does, so this route is never reached. Declare the static route first.",
                     refusal([todos, "/todos"], [BootFixtures::NewForm.new, "/todos"])
      end

      it "refuses a route with the same shape as one before it" do
        assert_equal "BootFixtures::SameShape#find (GET /:todo_id)\n  " \
                     "BootFixtures::SameShape#show (GET /:id) is tried first and matches exactly the same paths, " \
                     "so this route is never reached. Remove one of them, or change a path.",
                     refusal([BootFixtures::SameShape.new, "/"])
      end

      it "allows a static route declared before a parameter in its place" do
        assert_equal 2, boot([BootFixtures::StaticFirst.new, "/"]).size
      end

      it "allows the root path after a parameter, which never matches an empty segment" do
        assert_equal 2, boot([BootFixtures::RootLast.new, "/"]).size
      end
    end

    describe "the method" do
      it "refuses a method the class doesn't have" do
        assert_equal "BootFixtures::Unrouted#index (GET /)\n  " \
                     "BootFixtures::Unrouted has no public method `index`. " \
                     "Define it as a public method, or change to:.",
                     refusal([BootFixtures::Unrouted.new, "/"])
      end

      it "refuses a private method" do
        assert_match(/has no public method `index`/, refusal([BootFixtures::Private.new, "/"]))
      end

      it "refuses a protected method" do
        assert_match(/has no public method `index`/, refusal([BootFixtures::Protected.new, "/"]))
      end

      it "refuses a method that takes a positional argument" do
        assert_equal "BootFixtures::Positional#show (GET /:id)\n  " \
                     "The method takes positional arguments or **rest, but Skyward API passes only named keywords. " \
                     "Take each input as a keyword, such as `id:`.",
                     refusal([BootFixtures::Positional.new, "/"])
      end

      it "refuses a method that takes **rest" do
        assert_match(/takes positional arguments or \*\*rest/, refusal([BootFixtures::KeywordRest.new, "/"]))
      end

      it "refuses a method with no signature that takes a positional argument" do
        assert_match(/takes positional arguments or \*\*rest/, refusal([BootFixtures::UnsignedPositional.new, "/"]))
      end

      it "takes a class with no signature as untyped, with the method's own keywords" do
        greet = endpoint(boot([BootFixtures::Unsigned.new, "/"]), :greet)
        expected = [
          [keyword(:name, :path, true, untyped), keyword(:shout, :query, false, untyped),
           keyword(:request, :request, false, Skyward::API::Boot::REQUEST_TYPE)],
          [untyped]
        ]

        assert_equal expected, [greet.keywords, greet.returns]
      end

      it "takes a method with no signature as untyped" do
        index = endpoint(boot([BootFixtures::UnsignedMethod.new, "/"]), :index)

        assert_equal [[], [untyped]], [index.keywords, index.returns]
      end
    end

    describe "a stale signature" do
      it "refuses a signature whose keywords have other names" do
        assert_equal "BootFixtures::Renamed#index (GET /)\n  " \
                     "The method takes (limit:), but its signature takes (count: Integer), " \
                     "so the signature is stale. Run rbs-inline, or update the signature.",
                     refusal([BootFixtures::Renamed.new, "/"])
      end

      it "refuses a signature that requires a keyword the method makes optional" do
        assert_match(
          /The method takes \(\?limit:\), but its signature takes \(limit: Integer\)/,
          refusal([BootFixtures::MadeOptional.new, "/"])
        )
      end

      it "refuses a signature with positional parameters" do
        assert_match(
          /The method takes \(id:\), but its signature takes \(Integer id\)/,
          refusal([BootFixtures::SignedPositionally.new, "/"])
        )
      end

      it "refuses a signature with untyped parameters" do
        assert_match(
          /The method takes \(id:\), but its signature takes \(\?\)/,
          refusal([BootFixtures::SignedUntyped.new, "/"])
        )
      end
    end

    it "refuses a path parameter the method has no keyword for" do
      assert_equal "BootFixtures::Unnamed#show (GET /:id)\n  " \
                   "The route has a path parameter :id, but the method has no `id:` keyword. " \
                   "Add `id:` to the method, or rename the path parameter.",
                   refusal([BootFixtures::Unnamed.new, "/"])
    end

    describe "keywords and the return type" do
      it "takes a keyword named in the path from the path" do
        assert_equal [keyword(:id, :path, true, integer)], endpoint(boot([todos, "/"]), :show).keywords
      end

      it "takes body: from the body, with any readable type" do
        body = types::Record.new(
          fields: [types::Field.new(name: :title, type: types::Scalar.new(name: :string), required: true)]
        )

        assert_equal [keyword(:body, :body, true, body)], endpoint(boot([todos, "/"]), :create, "POST").keywords
      end

      describe "request:" do
        let(:requesting) { boot([BootFixtures::Requesting.new, "/"]) }

        it "takes request: from the request, never the query string" do
          expected = [keyword(:request, :request, true, Skyward::API::Boot::REQUEST_TYPE)]

          assert_equal expected, endpoint(requesting, :index).keywords
        end

        it "takes request: with a default" do
          assert_equal keyword(:request, :request, false, Skyward::API::Boot::REQUEST_TYPE),
                       endpoint(requesting, :show).keywords.last
        end

        it "takes request: typed untyped, as rbs-inline writes it, as the request" do
          assert_equal keyword(:request, :request, false, Skyward::API::Boot::REQUEST_TYPE),
                       endpoint(boot([BootFixtures::Inlined.new, "/"]), :greet).keywords.last
        end

        it "refuses request: typed as anything but Skyward::Request" do
          assert_equal "BootFixtures::MistypedRequest#index (GET /)\n  " \
                       "`request:` is always the Skyward::Request, but its signature types it as String. " \
                       "Type it as Skyward::Request, or rename the keyword.",
                       refusal([BootFixtures::MistypedRequest.new, "/"])
        end
      end

      it "takes any other keyword from the query string, in the method's order, required or not" do
        expected = [
          keyword(:done, :query, false, types::Nullable.new(type: types::Scalar.new(name: :bool))),
          keyword(:tags, :query, false, types::ArrayOf.new(type: types::Enum.new(symbols: %i[low high])))
        ]

        assert_equal expected, endpoint(boot([todos, "/"]), :index).keywords
      end

      it "refuses a keyword whose type can't be read" do
        assert_equal "BootFixtures::TupleQuery#index (GET /)\n  " \
                     "The type of `range:` can't be read: Skyward API doesn't read [ Integer, Integer ]. " \
                     "Use Array[T], or a record instead.",
                     refusal([BootFixtures::TupleQuery.new, "/"])
      end

      it "names the class and reader where an unreadable type was found" do
        assert_equal "BootFixtures::HashBody#create (POST /)\n  " \
                     "The type of `body:` can't be read: Skyward API doesn't read Hash[Symbol, untyped], " \
                     "at BootFixtures::Holder#tags. Use Hash[String, T] (only String keys are supported) instead.",
                     refusal([BootFixtures::HashBody.new, "/"])
      end

      it "refuses an array in the path" do
        assert_equal "BootFixtures::ArrayPath#show (GET /:ids)\n  " \
                     "`ids:` comes from the path, which can't carry an array. " \
                     "Give it a type such as String, Integer or an enum.",
                     refusal([BootFixtures::ArrayPath.new, "/"])
      end

      it "refuses a hash in the path" do
        assert_match(
          /`scores:` comes from the path, which can't carry a hash\./,
          refusal([BootFixtures::HashPath.new, "/"])
        )
      end

      it "refuses a class in the path" do
        assert_match(
          /`todo:` comes from the path, which can't carry BootFixtures::Todo, a class\./,
          refusal([BootFixtures::ClassPath.new, "/"])
        )
      end

      it "refuses a record in the query string" do
        assert_equal "BootFixtures::RecordQuery#index (GET /)\n  " \
                     "`filter:` comes from the query string, which can't carry a record. " \
                     "Give it a type such as String, Integer or an array of them, or take it in `body:`.",
                     refusal([BootFixtures::RecordQuery.new, "/"])
      end

      it "refuses a nullable hash in the query string" do
        assert_match(
          /`scores:` comes from the query string, which can't carry a hash\./,
          refusal([BootFixtures::HashQuery.new, "/"])
        )
      end

      it "refuses a nullable class in the query string" do
        assert_match(
          /`like:` comes from the query string, which can't carry BootFixtures::Todo, a class\./,
          refusal([BootFixtures::NullableClassQuery.new, "/"])
        )
      end

      it "refuses a union with a class in the query string" do
        assert_match(
          /`near:` comes from the query string, which can't carry BootFixtures::Todo, a class\./,
          refusal([BootFixtures::UnionQuery.new, "/"])
        )
      end

      it "refuses an array of arrays in the query string" do
        assert_match(
          /`grid:` comes from the query string, which can't carry an array of arrays\./,
          refusal([BootFixtures::NestedArrayQuery.new, "/"])
        )
      end

      it "records each member of a union return type" do
        assert_equal [todo, types::Enum.new(symbols: [:gone])], endpoint(boot([todos, "/"]), :show).returns
      end

      it "records each member of a nullable return type, nil among them" do
        expected = [todo, types::Enum.new(symbols: [:gone]), types::Literal.new(value: nil)]

        assert_equal expected, endpoint(boot([todos, "/"]), :destroy, "DELETE").returns
      end

      it "records any other return type as its only member" do
        assert_equal [types::ArrayOf.new(type: todo)], endpoint(boot([todos, "/"]), :index).returns
      end

      it "refuses a return type that can't be read" do
        assert_equal "BootFixtures::HashReturn#index (GET /)\n  " \
                     "The return type can't be read: Skyward API doesn't read Hash[Symbol, untyped]. " \
                     "Use Hash[String, T] (only String keys are supported) instead.",
                     refusal([BootFixtures::HashReturn.new, "/"])
      end

      it "compiles the keywords into the endpoint's inputs, reading a body up to max_body_size" do
        inputs = endpoint(boot([todos, "/"]), :create, "POST").inputs
        env = { "CONTENT_TYPE" => "application/json", "rack.input" => StringIO.new('{"title":"Ship it"}') }

        assert_equal :content_too_large, inputs.call(env, {})
      end

      it "labels a type the reader refuses outright" do
        assert_equal "BootFixtures::SelfReferring#index (GET /)\n  " \
                     "Can't read BootFixtures::Node: it refers to itself through " \
                     "BootFixtures::Node -> BootFixtures::Node",
                     refusal([BootFixtures::SelfReferring.new, "/"])
      end
    end

    describe "response values in the return type" do
      let(:responding) { boot([BootFixtures::Responding.new, "/"]) }

      def response(klass) = Skyward::API::Router::Response.new(klass:)

      it "records each response value of a nullable union, nil among them" do
        expected = [
          response(Skyward::NoContent),
          response(Skyward::Conflict),
          response(Skyward::Unprocessable),
          types::Literal.new(value: nil)
        ]

        assert_equal expected, endpoint(responding, :destroy, "DELETE").returns
      end

      describe "a Rack triple" do
        let(:racking) { boot([BootFixtures::Racking.new, "/"]) }

        it "records Skyward::rack as a Rack triple, among the other members" do
          expected = [todo, response(Skyward::NotFound), Skyward::API::Router::Rack.new]

          assert_equal expected, endpoint(racking, :download).returns
        end

        it "records the tuple Skyward::rack names as a Rack triple" do
          assert_equal [Skyward::API::Router::Rack.new], endpoint(racking, :written).returns
        end
      end

      it "records a response value as its class" do
        assert_equal [todo, response(Skyward::NotFound)], endpoint(responding, :show).returns
      end

      it "records Created[T] with the type of its value" do
        assert_equal [Skyward::API::Router::Created.new(type: todo)], endpoint(responding, :create, "POST").returns
      end

      it "refuses a Created without the type of its value" do
        assert_equal "BootFixtures::CreatedBare#create (POST /)\n  " \
                     "The return type can't be read: Skyward API doesn't read Skyward::Created. " \
                     "Use Created[T] instead.",
                     refusal([BootFixtures::CreatedBare.new, "/"])
      end

      it "refuses a Created whose value's type can't be read" do
        assert_equal "BootFixtures::CreatedHash#create (POST /)\n  " \
                     "The return type can't be read: Skyward API doesn't read Hash[Symbol, untyped]. " \
                     "Use Hash[String, T] (only String keys are supported) instead.",
                     refusal([BootFixtures::CreatedHash.new, "/"])
      end
    end

    it "compiles a serializer for the return type, whose errors start with the route's label" do
      error = assert_raises(Skyward::API::ReturnTypeError) { endpoint(boot([todos, "/"]), :show).serializer.call(nil) }

      assert_equal "BootFixtures::Todos#show (GET /:id) returned nil, which isn't BootFixtures::Todo | :gone",
                   error.message
    end

    describe "strict:" do
      it "boots endpoints whose keywords and return type are typed" do
        assert_equal 5, boot([todos, "/todos"], strict: true).size
      end

      it "refuses every endpoint with no signature, each with its label" do
        message = refusal(
          [todos, "/todos"], [BootFixtures::Unsigned.new, "/"], [BootFixtures::UnsignedMethod.new, "/"], strict: true
        )

        assert_equal "BootFixtures::Unsigned#greet (GET /:name)\n  " \
                     "It has no RBS signature, but strict: true refuses an untyped endpoint. " \
                     "Annotate it and run rbs-inline, or check `signatures:`.\n" \
                     "BootFixtures::UnsignedMethod#index (GET /)\n  " \
                     "It has no RBS signature, but strict: true refuses an untyped endpoint. " \
                     "Annotate it and run rbs-inline, or check `signatures:`.",
                     message
      end

      it "names each keyword and return type a signature leaves untyped, but not request:" do
        assert_equal "BootFixtures::Inlined#greet (GET /:name)\n  " \
                     "Its signature leaves `name:`, `shout:` and the return type untyped, " \
                     "but strict: true refuses an untyped endpoint. Give each a type.",
                     refusal([BootFixtures::Inlined.new, "/"], strict: true)
      end

      it "names a single untyped keyword" do
        assert_match(
          /leaves `id:` untyped, but strict: true refuses an untyped endpoint\. Give it a type\.\z/,
          refusal([BootFixtures::UntypedKeyword.new, "/"], strict: true)
        )
      end

      it "names a keyword typed untyped?" do
        assert_match(/leaves `limit:` untyped/, refusal([BootFixtures::NullableUntypedKeyword.new, "/"], strict: true))
      end

      it "boots untyped inside a type, as in Array[untyped]" do
        assert_equal 1, boot([BootFixtures::NestedUntyped.new, "/"], strict: true).size
      end
    end
  end
end
