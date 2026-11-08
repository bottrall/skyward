# frozen_string_literal: true

require "json"

class Skyward::API::Serializer
  JSON_TYPE = { "content-type" => "application/json" }.freeze #: Hash[String, String]

  Problem = Data.define(
    :status, #: Integer
    :title #: String
  )

  PROBLEMS = {
    Skyward::NotFound => Problem.new(status: 404, title: "Not Found"),
    Skyward::Conflict => Problem.new(status: 409, title: "Conflict"),
    Skyward::Unprocessable => Problem.new(status: 422, title: "Unprocessable Content")
  }.freeze #: Hash[Class, Problem]

  # Every response value but Skyward::Created, which carries a type of its own.
  RESPONSES = [Skyward::NoContent, *PROBLEMS.keys].freeze #: Array[Class]

  UNTYPED = Skyward::Types::Scalar.new(name: :untyped) #: Skyward::Types::Scalar

  # @rbs @label: String
  # @rbs @writer: Skyward::API::Writers::Writer

  # @rbs returns: Array[Skyward::API::Router::returned]
  # @rbs label: String
  # @rbs return: void
  def initialize(returns, label:)
    @label = label
    @writer = Skyward::API::Writers.union(returns.map { |member| compile(member) })
    freeze
  end

  # The whole body is written before anything is answered, so a value that doesn't fit sends none of it.
  # @rbs value: untyped
  # @rbs return: Skyward::API::App::response
  def call(value)
    response = @writer.write.call(value, "")
    case response
    when Skyward::API::Writers::Misfit then raise Skyward::API::ReturnTypeError, message(response)
    else response
    end
  end

  private

  # @rbs member: Skyward::API::Router::returned
  # @rbs return: Skyward::API::Writers::Writer
  def compile(member)
    case member
    when Skyward::API::Router::Created then created(Skyward::API::Writers.writer(member.type))
    when Skyward::API::Router::Response then response(member.klass)
    when UNTYPED then untyped
    else ok(Skyward::API::Writers.writer(member))
    end
  end

  # Untyped code can return any response value.
  # @rbs return: Skyward::API::Writers::Writer
  def untyped
    writer = Skyward::API::Writers.writer(UNTYPED)
    responses = [created(writer), *RESPONSES.map { |klass| response(klass) }, ok(writer)]
    Skyward::API::Writers.union(responses).with(name: "untyped")
  end

  # @rbs writer: Skyward::API::Writers::Writer
  # @rbs return: Skyward::API::Writers::Writer
  def ok(writer)
    writer.with(write: ->(value, at) { json(writer.write.call(value, at), 200, JSON_TYPE.dup) })
  end

  # @rbs writer: Skyward::API::Writers::Writer
  # @rbs return: Skyward::API::Writers::Writer
  def created(writer)
    Skyward::API::Writers.checked(
      "Skyward::Created[#{writer.name}]",
      ->(given) { given.is_a?(Skyward::Created) },
      lambda do |given, at|
        json(writer.write.call(given.value, "#{at}.value"), 201, { **JSON_TYPE, **given.headers })
      end
    )
  end

  # @rbs klass: Class
  # @rbs return: Skyward::API::Writers::Writer
  def response(klass)
    problem = PROBLEMS.fetch(klass, nil)
    answer =
      if problem then ->(given, _) { problem_response(problem, given) }
      else ->(given, _) { [204, given.headers.dup, []] }
      end #: ^(untyped, String) -> Skyward::API::App::response
    Skyward::API::Writers.checked(klass.name.to_s, ->(given) { given.is_a?(klass) }, answer)
  end

  # @rbs problem: Problem
  # @rbs given: untyped
  # @rbs return: Skyward::API::App::response
  def problem_response(problem, given)
    body = { type: "about:blank", title: problem.title, status: problem.status, detail: given.detail }.compact
    [problem.status, { "content-type" => "application/problem+json", **given.headers }, [JSON.generate(body)]]
  end

  # @rbs written: untyped
  # @rbs status: Integer
  # @rbs headers: Hash[String, String]
  # @rbs return: untyped
  def json(written, status, headers)
    written.is_a?(Skyward::API::Writers::Misfit) ? written : [status, headers, [JSON.generate(written)]]
  end

  # @rbs misfit: Skyward::API::Writers::Misfit
  # @rbs return: String
  def message(misfit)
    return "#{@label} returned #{misfit.got}, which isn't #{misfit.expected}" if misfit.at.empty?

    "#{@label} returned #{misfit.got} at #{misfit.at.delete_prefix(".")}, which isn't #{misfit.expected}, " \
      "in its return type #{@writer.name}"
  end
end
