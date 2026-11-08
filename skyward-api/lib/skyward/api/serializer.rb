# frozen_string_literal: true

require "json"

class Skyward::API::Serializer
  JSON_TYPE = { "content-type" => "application/json" }.freeze #: Hash[String, String]

  Problem = Data.define(
    :status, #: Integer
    :title #: String
  )

  PROBLEMS = {
    Skyward::API::Responses::BadRequest => Problem.new(status: 400, title: "Bad Request"),
    Skyward::API::Responses::Unauthorized => Problem.new(status: 401, title: "Unauthorized"),
    Skyward::API::Responses::Forbidden => Problem.new(status: 403, title: "Forbidden"),
    Skyward::API::Responses::NotFound => Problem.new(status: 404, title: "Not Found"),
    Skyward::API::Responses::Conflict => Problem.new(status: 409, title: "Conflict"),
    Skyward::API::Responses::Unprocessable => Problem.new(status: 422, title: "Unprocessable Content")
  }.freeze #: Hash[Class, Problem]

  # Every response value but Skyward::API::Responses::Created, which carries a type of its own.
  RESPONSES = [
    Skyward::API::Responses::NoContent,
    *PROBLEMS.keys,
    Skyward::API::Responses::Redirect
  ].freeze #: Array[Class]

  UNTYPED = Skyward::Core::Types::Scalar.new(name: :untyped) #: Skyward::Core::Types::Scalar

  # @rbs @label: String
  # @rbs @writer: Writers::Writer

  # @rbs returns: Array[Skyward::API::Routing::Router::returned]
  # @rbs label: String
  # @rbs return: void
  def initialize(returns, label:)
    @label = label
    @writer = Writers.union(returns.map { |member| compile(member) })
    freeze
  end

  # The whole body is written before anything is answered, so a value that doesn't fit sends none of it.
  # @rbs value: untyped
  # @rbs return: Skyward::API::rack
  def call(value)
    response = @writer.write.call(value, "")
    case response
    when Writers::Misfit then raise Skyward::API::ReturnTypeError, message(response)
    else response
    end
  end

  private

  # @rbs member: Skyward::API::Routing::Router::returned
  # @rbs return: Writers::Writer
  def compile(member)
    case member
    when Skyward::API::Routing::Router::Created then created(Writers.writer(member.type))
    when Skyward::API::Routing::Router::Response then response(member.klass)
    when Skyward::API::Routing::Router::Rack then rack
    when UNTYPED then untyped
    else ok(Writers.writer(member))
    end
  end

  # Untyped code can return any response value.
  # @rbs return: Writers::Writer
  def untyped
    writer = Writers.writer(UNTYPED)
    responses = [created(writer), *RESPONSES.map { |klass| response(klass) }, ok(writer)]
    Writers.union(responses).with(name: "untyped")
  end

  # @rbs writer: Writers::Writer
  # @rbs return: Writers::Writer
  def ok(writer)
    writer.with(write: ->(value, at) { json(writer.write.call(value, at), 200, JSON_TYPE.dup) })
  end

  # @rbs writer: Writers::Writer
  # @rbs return: Writers::Writer
  def created(writer)
    Writers.checked(
      "Skyward::API::Responses::Created[#{writer.name}]",
      ->(given) { given.is_a?(Skyward::API::Responses::Created) },
      lambda do |given, at|
        json(writer.write.call(given.value, "#{at}.value"), 201, { **JSON_TYPE, **given.headers })
      end
    )
  end

  # @rbs klass: Class
  # @rbs return: Writers::Writer
  def response(klass)
    problem = PROBLEMS.fetch(klass, nil)
    answer =
      if problem then ->(given, _) { problem_response(problem, given) }
      elsif klass == Skyward::API::Responses::Redirect then ->(given, _) { [given.status, { "location" => given.to, **given.headers }, []] }
      else ->(given, _) { [204, given.headers.dup, []] }
      end #: ^(untyped, String) -> Skyward::API::Assembly::Dispatcher::response
    Writers.checked(klass.name.to_s, ->(given) { given.is_a?(klass) }, answer)
  end

  # @rbs return: Writers::Writer
  def rack
    Writers.checked(
      "Skyward::API::rack",
      ->(given) { given.is_a?(Array) && given.size == 3 && given[0].is_a?(Integer) && given[1].is_a?(Hash) },
      ->(given, _) { given }
    )
  end

  # @rbs problem: Problem
  # @rbs given: untyped
  # @rbs return: Skyward::API::Assembly::Dispatcher::response
  def problem_response(problem, given)
    body = { type: "about:blank", title: problem.title, status: problem.status, detail: given.detail }.compact
    [problem.status, { "content-type" => "application/problem+json", **given.headers }, [JSON.generate(body)]]
  end

  # @rbs written: untyped
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: untyped
  def json(written, status, headers)
    written.is_a?(Writers::Misfit) ? written : [status, headers, [JSON.generate(written)]]
  end

  # @rbs misfit: Writers::Misfit
  # @rbs return: String
  def message(misfit)
    return "#{@label} returned #{misfit.got}, which isn't #{misfit.expected}" if misfit.at.empty?

    "#{@label} returned #{misfit.got} at #{misfit.at.delete_prefix(".")}, which isn't #{misfit.expected}, " \
      "in its return type #{@writer.name}"
  end
end
