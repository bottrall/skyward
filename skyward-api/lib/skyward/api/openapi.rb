# frozen_string_literal: true

require "json"

module Skyward::API::OpenAPI
  extend self

  # @rbs!
  #   type schema = Hash[Symbol, untyped]
  #   type form = :request | :response

  Answer = Data.define(
    :status, #: String
    :media_type, #: String?
    :schema #: schema?
  )

  PATH = "/openapi.json" #: String

  SERVED = {
    PATH => "the OpenAPI document",
    Skyward::API::Docs::PATH => "the API reference"
  }.freeze #: Hash[String, String]

  # OpenAPI's pattern for the name of a component.
  NAME = /\A[A-Za-z0-9._-]+\z/ #: Regexp

  JSON_TYPE = "application/json" #: String

  PROBLEM_TYPE = "application/problem+json" #: String

  SCALARS = {
    integer: { type: "integer" },
    float: { type: "number" },
    string: { type: "string" },
    bool: { type: "boolean" },
    date: { type: "string", format: "date" },
    time: { type: "string", format: "date-time" },
    untyped: {} #: schema
  }.freeze #: Hash[Skyward::Types::scalar, schema]

  NULL = { type: "null" }.freeze #: schema

  PROBLEM = { "$ref": "#/components/schemas/Problem" }.freeze #: schema

  PROBLEM_SCHEMA = {
    type: "object",
    properties: {
      type: { type: "string" },
      title: { type: "string" },
      status: { type: "integer" },
      detail: { type: "string" },
      errors: {
        type: "array",
        items: {
          type: "object",
          properties: { at: { type: "string" }, message: { type: "string" } },
          required: %w[at message]
        }
      }
    },
    required: %w[type title status]
  }.freeze #: schema

  NO_CONTENT = Answer.new(status: "204", media_type: nil, schema: nil) #: Answer

  # A redirect's status is chosen when it's made, so it's documented as the range.
  REDIRECT = Answer.new(status: "3XX", media_type: nil, schema: nil) #: Answer

  RACK = Answer.new(status: "default", media_type: nil, schema: nil) #: Answer

  INVALID = Answer.new(status: "422", media_type: PROBLEM_TYPE, schema: PROBLEM) #: Answer

  REFUSED = [
    Answer.new(status: "413", media_type: PROBLEM_TYPE, schema: PROBLEM),
    Answer.new(status: "415", media_type: PROBLEM_TYPE, schema: PROBLEM)
  ].freeze #: Array[Answer]

  LOCATION = { location: { schema: { type: "string" } } }.freeze #: Hash[Symbol, untyped]

  DESCRIPTIONS = {
    "200" => "OK",
    "201" => "Created",
    "204" => "No Content",
    "3XX" => "Redirect",
    **Skyward::API::Serializer::PROBLEMS.values.to_h { |problem| [problem.status.to_s, problem.title] },
    **Skyward::API::App::INPUT_TITLES.transform_keys(&:to_s),
    "default" => "A Rack response, whose status and content are known only when it's sent"
  }.freeze #: Hash[String, String]

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs static: Skyward::API::Static
  # @rbs title: String
  # @rbs version: String
  # @rbs description: String?
  # @rbs schema_names: Hash[Class, String]
  # @rbs return: String
  def json(endpoints, static:, title:, version:, description:, schema_names:)
    types = endpoints.flat_map { |endpoint| types(endpoint).flat_map { |type| named(type) } }.uniq
    names = served(endpoints, static) || operation_ids(endpoints) || names(types, schema_names)
    case names
    when String then raise Skyward::BootError, names
    else JSON.generate(document(endpoints, types, { title:, version:, description: }.compact, names))
    end
  end

  private

  # The request: keyword is Skyward's, not part of the HTTP contract.
  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: Array[Skyward::API::Router::Keyword]
  def described(endpoint) = endpoint.keywords.reject { |keyword| keyword.source == :request }

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: Array[Skyward::Types::t]
  def types(endpoint)
    returned = endpoint.returns.filter_map do |member|
      case member
      when Skyward::API::Router::Created then member.type
      when Skyward::API::Router::Response, Skyward::API::Router::Rack then nil
      else member
      end
    end
    [*described(endpoint).map(&:type), *returned]
  end

  # @rbs type: Skyward::Types::t
  # @rbs return: Array[Skyward::Types::Named]
  def named(type)
    case type
    when Skyward::Types::Nullable, Skyward::Types::ArrayOf, Skyward::Types::HashOf then named(type.type)
    when Skyward::Types::Record then type.fields.flat_map { |field| named(field.type) }
    when Skyward::Types::Named then [type, *type.fields.flat_map { |field| named(field.type) }]
    when Skyward::Types::Union then type.types.flat_map { |member| named(member) }
    else []
    end
  end

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs static: Skyward::API::Static
  # @rbs return: String?
  def served(endpoints, static)
    SERVED.lazy.filter_map { |at, serves| taken(at, serves, endpoints, static) }.first
  end

  # @rbs at: String
  # @rbs serves: String
  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs static: Skyward::API::Static
  # @rbs return: String?
  def taken(at, serves, endpoints, static)
    routed = endpoints.find { |endpoint| path(endpoint.pattern) == at }
    if routed
      return "#{routed.label}\n  With docs: true, #{at} serves #{serves}. Change the route's path, or leave out docs:."
    end

    file = static.file(at)
    return unless file

    "static serves #{file} at #{at}, where docs: true serves #{serves}. Move the file, or leave out docs:."
  end

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs return: String?
  def operation_ids(endpoints)
    id, same = endpoints.group_by { |endpoint| operation_id(endpoint) }.find { |_, shared| shared.size > 1 }
    return unless same

    first = same.fetch(0)
    second = same.fetch(1)
    "#{second.label}\n  Its OpenAPI operation ID, #{id}, is #{first.label}'s too, " \
      "but each operation needs its own. With docs: true, route each method once, and mount each class once."
  end

  # @rbs types: Array[Skyward::Types::Named]
  # @rbs schema_names: Hash[Class, String]
  # @rbs return: Hash[Class, String] | String
  def names(types, schema_names)
    chosen = types.to_h { |type| [type.klass, schema_names.fetch(type.klass) { dotted(type.name) }] }
    invalid, name = chosen.find { |_, named| !NAME.match?(named) }
    if invalid
      return "#{invalid}'s schema name, #{name.inspect}, isn't one OpenAPI allows: use only letters, digits, " \
             "., - and _. Name it with Skyward.app(schema_names:)."
    end

    taken = [["Problem", "Skyward API's problem+json"], *chosen.map { |klass, named| [named, klass.to_s] }]
    same = taken.group_by(&:first).values.find { |shared| shared.size > 1 }
    return chosen unless same

    (name, first), (_, second) = same.fetch(0), same.fetch(1)
    "#{first} and #{second} both have the schema name #{name}, but each schema needs its own. " \
      "Name one of them with Skyward.app(schema_names:)."
  end

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs types: Array[Skyward::Types::Named]
  # @rbs info: Hash[Symbol, String]
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def document(endpoints, types, info, names)
    {
      openapi: "3.1.0",
      info:,
      tags: endpoints.uniq { |endpoint| endpoint.api.class }.map do |endpoint|
        { name: tag(endpoint), description: endpoint.api.class.class_description }.compact
      end,
      paths: endpoints.group_by { |endpoint| path(endpoint.pattern) }.transform_values do |routed|
        routed.to_h { |endpoint| [endpoint.verb.downcase, operation(endpoint, names)] }
      end,
      components: { schemas: components(endpoints, types, names) }
    }
  end

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def operation(endpoint, names)
    bodies, others = described(endpoint).partition { |keyword| keyword.source == :body }
    body = bodies.first
    parameters = others.map { |keyword| parameter(keyword, names) }
    {
      tags: [tag(endpoint)],
      summary: endpoint.summary,
      description: endpoint.description,
      operationId: operation_id(endpoint),
      parameters: (parameters unless parameters.empty?),
      requestBody: (request_body(body, names) if body),
      responses: responses(endpoint, body, names)
    }.compact
  end

  # A path or query value can't be null, so its schema leaves null out, and it's
  # always a String, so an untyped one is a string.
  # @rbs keyword: Skyward::API::Router::Keyword
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def parameter(keyword, names)
    type = keyword.type
    carried = type.is_a?(Skyward::Types::Nullable) ? type.type : type
    {
      name: keyword.name,
      in: keyword.source,
      required: keyword.source == :path || required?(keyword.required, type, :request),
      schema: carried == Skyward::API::Serializer::UNTYPED ? SCALARS.fetch(:string) : schema(carried, :request, names)
    }
  end

  # @rbs keyword: Skyward::API::Router::Keyword
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def request_body(keyword, names)
    {
      required: required?(keyword.required, keyword.type, :request),
      content: { JSON_TYPE => { schema: schema(keyword.type, :request, names) } }
    }
  end

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs body: Skyward::API::Router::Keyword?
  # @rbs names: Hash[Class, String]
  # @rbs return: Hash[String, schema]
  def responses(endpoint, body, names)
    answers = [
      *endpoint.returns.map { |member| answer(member, names) },
      *([INVALID] unless described(endpoint).empty?),
      *(REFUSED if body)
    ] #: Array[Answer]
    answers.group_by(&:status).sort_by(&:first).to_h { |status, same| [status, response(status, same)] }
  end

  # @rbs member: Skyward::API::Router::returned
  # @rbs names: Hash[Class, String]
  # @rbs return: Answer
  def answer(member, names)
    case member
    when Skyward::API::Router::Created
      Answer.new(status: "201", media_type: JSON_TYPE, schema: schema(member.type, :response, names))
    when Skyward::API::Router::Response then response_value(member.klass)
    when Skyward::API::Router::Rack then RACK
    else Answer.new(status: "200", media_type: JSON_TYPE, schema: schema(member, :response, names))
    end
  end

  # @rbs klass: Class
  # @rbs return: Answer
  def response_value(klass)
    problem = Skyward::API::Serializer::PROBLEMS.fetch(klass, nil)
    if problem then Answer.new(status: problem.status.to_s, media_type: PROBLEM_TYPE, schema: PROBLEM)
    elsif klass == Skyward::Redirect then REDIRECT
    else NO_CONTENT
    end
  end

  # Every answer with one status has the same media type, because the status says what's sent.
  # @rbs status: String
  # @rbs answers: Array[Answer]
  # @rbs return: schema
  def response(status, answers)
    base = { description: DESCRIPTIONS.fetch(status) }
    media_type = answers.fetch(0).media_type
    schemas = answers.filter_map(&:schema).uniq
    if media_type
      { **base, content: { media_type => { schema: schemas.one? ? schemas.fetch(0) : { oneOf: schemas } } } }
    elsif status == REDIRECT.status then { **base, headers: LOCATION }
    else
      base
    end
  end

  # @rbs endpoints: Array[Skyward::API::Router::Endpoint]
  # @rbs types: Array[Skyward::Types::Named]
  # @rbs names: Hash[Class, String]
  # @rbs return: Hash[String, schema]
  def components(endpoints, types, names)
    requested = endpoints.flat_map { |endpoint| described(endpoint).flat_map { |keyword| named(keyword.type) } }
    types.to_h do |type|
      [names.fetch(type.klass), object(type.fields, requested.include?(type) ? :request : :response, names)]
    end.merge("Problem" => PROBLEM_SCHEMA).sort_by(&:first).to_h
  end

  # @rbs type: Skyward::Types::t
  # @rbs form: form
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def schema(type, form, names)
    case type
    when Skyward::Types::Scalar then SCALARS.fetch(type.name)
    when Skyward::Types::Literal then type.value.nil? ? NULL : { const: type.value }
    when Skyward::Types::Enum then { type: "string", enum: type.symbols.map(&:name) }
    when Skyward::Types::Nullable then nullable(schema(type.type, form, names))
    when Skyward::Types::ArrayOf then { type: "array", items: schema(type.type, form, names) }
    when Skyward::Types::HashOf then { type: "object", additionalProperties: schema(type.type, form, names) }
    when Skyward::Types::Record then object(type.fields, form, names)
    when Skyward::Types::Named then { "$ref": "#/components/schemas/#{names.fetch(type.klass)}" }
    else { oneOf: type.types.map { |member| schema(member, form, names) } }
    end
  end

  # @rbs schema: schema
  # @rbs return: schema
  def nullable(schema)
    type = schema[:type]
    type.is_a?(String) && !schema.key?(:enum) ? schema.merge(type: [type, "null"]) : { anyOf: [schema, NULL] }
  end

  # @rbs fields: Array[Skyward::Types::Field]
  # @rbs form: form
  # @rbs names: Hash[Class, String]
  # @rbs return: schema
  def object(fields, form, names)
    {
      type: "object",
      properties: fields.to_h { |field| [field.name, schema(field.type, form, names)] },
      required: fields.filter_map { |field| field.name if required?(field.required, field.type, form) }
    }
  end

  # A request may leave out a nullable value, which arrives as nil, but a response always writes it.
  # @rbs required: bool
  # @rbs type: Skyward::Types::t
  # @rbs form: form
  # @rbs return: bool
  def required?(required, type, form) = required && (form == :response || !type.is_a?(Skyward::Types::Nullable))

  # @rbs pattern: Array[String | Symbol]
  # @rbs return: String
  def path(pattern) = pattern.map { |part| part.is_a?(Symbol) ? "{#{part}}" : part }.join("/")

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: String
  def tag(endpoint) = dotted(endpoint.api.class.name)

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: String
  def operation_id(endpoint) = "#{tag(endpoint)}_#{endpoint.to}"

  # @rbs name: String
  # @rbs return: String
  def dotted(name) = name.gsub("::", ".")
end
