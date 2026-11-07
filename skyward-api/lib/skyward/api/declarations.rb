# frozen_string_literal: true

# @rbs module-self Class
module Skyward::API::Declarations
  PARAMETER_NAME = /\A[a-z_]\w*\z/ #: Regexp

  # @rbs @routes: Array[Skyward::API::Route]?
  # @rbs @class_description: String?

  # @rbs return: Array[Skyward::API::Route]
  def routes = @routes || []

  # @rbs return: String?
  def class_description = @class_description

  # @rbs text: String
  # @rbs return: void
  def description(text)
    raise ArgumentError, "#{self} already has a description" if @class_description

    @class_description = text.dup.freeze
  end

  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def get(path, to:, summary: nil, description: nil)
    declare(:get, path, to, summary, description)
  end

  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def post(path, to:, summary: nil, description: nil)
    declare(:post, path, to, summary, description)
  end

  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def put(path, to:, summary: nil, description: nil)
    declare(:put, path, to, summary, description)
  end

  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def patch(path, to:, summary: nil, description: nil)
    declare(:patch, path, to, summary, description)
  end

  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def delete(path, to:, summary: nil, description: nil)
    declare(:delete, path, to, summary, description)
  end

  private

  # @rbs subclass: Class
  # @rbs return: void
  def inherited(subclass)
    super
    subclass.instance_variable_set(:@routes, routes)
  end

  # @rbs verb: Symbol
  # @rbs path: String
  # @rbs to: Symbol
  # @rbs summary: String?
  # @rbs description: String?
  # @rbs return: void
  def declare(verb, path, to, summary, description)
    problem = problem_with(path, to)
    raise ArgumentError, "#{self} #{verb.upcase} #{path.inspect}: #{problem}" if problem

    route = Skyward::API::Route.new(
      verb:,
      path: path.dup.freeze,
      to:,
      summary: summary.dup.freeze,
      description: description.dup.freeze
    )
    @routes = [*routes, route].freeze
  end

  # Untyped: a caller that Steep doesn't check can pass anything.
  # @rbs path: untyped
  # @rbs to: untyped
  # @rbs return: String?
  def problem_with(path, to)
    return "the path must be a String that starts with /" unless path.is_a?(String) && path.start_with?("/")

    names = path.split("/").filter_map { |segment| segment.delete_prefix(":") if segment.start_with?(":") }
    invalid = names.find { |name| !PARAMETER_NAME.match?(name) }
    return "path parameter #{invalid.inspect} isn't a valid keyword name" if invalid

    repeated = names.find { |name| names.count(name) > 1 }
    return "path parameter #{repeated.inspect} is used more than once" if repeated

    "to: must be a Symbol, got #{to.inspect}" unless to.is_a?(Symbol)
  end
end
