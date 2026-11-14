# frozen_string_literal: true

class Skyward::API::Routing::Router
  # @rbs! type returned = Skyward::Core::Types::t | Created | Response | Rack

  Keyword = Data.define(
    :name, #: Symbol
    :source, #: :path | :query | :body | :request
    :required, #: bool
    :type #: Skyward::Core::Types::t
  )

  # Skyward::API::Responses::Created[T], which the reader can't read, so its value's type is read on its own.
  Created = Data.define(
    :type #: Skyward::Core::Types::t
  )

  Response = Data.define(
    :klass #: Class
  )

  Rack = Data.define

  # A provider without a signature has no value to check, so its value is nil.
  Provider = Data.define(
    :name, #: Symbol
    :callable, #: Skyward::API::_Provider
    :value, #: Array[RBS::Types::t]?
    :responses, #: Array[Response]
    :serializer #: Skyward::API::Serializer
  )

  Endpoint = Data.define(
    :verb, #: String
    :pattern, #: Array[String | Symbol]
    :api, #: Skyward::API
    :to, #: Symbol
    :label, #: String
    :summary, #: String?
    :description, #: String?
    :keywords, #: Array[Keyword]
    :providers, #: Array[Provider]
    :returns, #: Array[returned]
    :signature, #: String
    :inputs, #: Skyward::API::Inputs
    :serializer #: Skyward::API::Serializer
  )

  Match = Data.define(
    :api, #: Skyward::API
    :to, #: Symbol
    :inputs, #: Skyward::API::Inputs
    :params, #: Hash[Symbol, String]
    :serializer #: Skyward::API::Serializer
  )

  Target = Data.define(
    :index, #: Integer
    :endpoint, #: Endpoint
    :params #: Array[[Symbol, Integer]]
  )

  # First is the lowest index in or below the node, so a search can skip a node that can't beat what it has found.
  Node = Data.define(
    :literals, #: Hash[String, Node]
    :param, #: Node?
    :target, #: Target?
    :first #: Integer
  )

  METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze #: Array[String]

  # @rbs @trees: Hash[String, Node]

  # @rbs endpoints: Array[Endpoint]
  # @rbs return: void
  def initialize(endpoints)
    targets = endpoints.each_with_index.map do |endpoint, index|
      Target.new(index:, endpoint:, params: params_of(endpoint.pattern).freeze)
    end
    @trees = targets.group_by { |target| target.endpoint.verb }.transform_values { |group| build(group, 0) }.freeze
  end

  # @rbs verb: String
  # @rbs path: String
  # @rbs return: Match?
  def match(verb, path)
    segments = path.split('/', -1)
    target = search(@trees.fetch(verb == 'HEAD' ? 'GET' : verb, nil), segments, 0, nil)
    return unless target

    endpoint = target.endpoint
    params = target.params.to_h do |name, position|
      [name, Skyward::API::Routing::PercentEncoding.decode(segments[position])]
    end
    Match.new(api: endpoint.api, to: endpoint.to, inputs: endpoint.inputs, params:, serializer: endpoint.serializer)
  end

  # @rbs path: String
  # @rbs return: Array[String]
  def allowed(path)
    segments = path.split('/', -1)
    verbs = @trees.filter_map { |verb, tree| verb if search(tree, segments, 0, nil) }
    return [] if verbs.empty?

    implied = verbs.include?('GET') ? %w[HEAD OPTIONS] : %w[OPTIONS]
    METHODS & (verbs + implied)
  end

  private

  # @rbs pattern: Array[String | Symbol]
  # @rbs return: Array[[Symbol, Integer]]
  def params_of(pattern)
    pattern.each_with_index.filter_map { |part, position| [part, position] if part.is_a?(Symbol) }
  end

  # @rbs targets: Array[Target]
  # @rbs depth: Integer
  # @rbs return: Node
  def build(targets, depth)
    ending, deeper = targets.partition { |target| target.endpoint.pattern.length == depth }
    params, literals = deeper.partition { |target| target.endpoint.pattern.fetch(depth).is_a?(Symbol) }
    by_segment = literals.group_by { |target| target.endpoint.pattern.fetch(depth).to_s }
    # Targets come in index order, so a node's first target is its earliest.
    Node.new(
      literals: by_segment.transform_values { |group| build(group, depth + 1) }.freeze,
      param: params.empty? ? nil : build(params, depth + 1),
      target: ending.first,
      first: targets.fetch(0).index
    )
  end

  # @rbs node: Node?
  # @rbs segments: Array[String]
  # @rbs depth: Integer
  # @rbs best: Target?
  # @rbs return: Target?
  def search(node, segments, depth, best)
    return best unless node && (best.nil? || node.first < best.index)
    return earlier(node.target, best) if depth == segments.length

    segment = segments[depth]
    found = search(node.literals[segment], segments, depth + 1, best)
    segment.empty? ? found : search(node.param, segments, depth + 1, found)
  end

  # @rbs target: Target?
  # @rbs best: Target?
  # @rbs return: Target?
  def earlier(target, best)
    return best unless target && (best.nil? || target.index < best.index)

    target
  end
end
