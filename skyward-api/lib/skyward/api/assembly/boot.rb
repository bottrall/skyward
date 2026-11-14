# frozen_string_literal: true

module Skyward::API::Assembly::Boot
  extend self

  UNNAMED = %i[req opt rest keyrest].freeze #: Array[Symbol]

  KEYWORD = %i[keyreq key].freeze #: Array[Symbol]

  RACK = ['::Skyward::API::rack', '[::Integer, ::Hash[::String, ::String], untyped]'].map do |type|
    RBS::Parser.parse_type(type)
  end.freeze #: Array[RBS::Types::t?]

  REQUEST = RBS::Parser.parse_type('::Skyward::API::Request') #: RBS::Types::t?

  REQUEST_TYPE = Skyward::Core::Types::Named.new(
    name: 'Skyward::API::Request',
    klass: Skyward::API::Request,
    fields: []
  ) #: Skyward::Core::Types::Named

  # A method with no signature is read as if each keyword and the return were
  # untyped, which is what rbs-inline writes for a method with no annotations.
  ANY = RBS::Types::Bases::Any.new(location: nil) #: RBS::Types::Bases::Any

  Refusal = Data.define(
    :problem, #: String
    :spots, #: Array[Skyward::Core::Diagnostics::Spot]
    :hint #: String?
  )

  # @rbs (Array[Skyward::API::Assembly::Builder::Mount] mounts,
  #       providers: Hash[Symbol, Skyward::API::_Provider & Object], reader: Skyward::Core::Types::Reader,
  #       max_body_size: Integer, strict: bool) ->
  #       Array[Skyward::API::Routing::Router::Endpoint]
  def endpoints(mounts, providers:, reader:, max_body_size:, strict:)
    single = providers.filter_map { |name, callable| single_object(name, callable) }.first
    raise Skyward::Core::BootError, single if single

    provided = providers.to_h { |name, callable| [name, provider(name, callable, reader)] }
    none = [] #: Array[[Skyward::API::Endpoints::Route, Skyward::API::Routing::Router::Endpoint]]
    routed = mounts.reduce(none) do |booted, mount|
      mount.api.class.routes.reduce(booted) do |so_far, route|
        [*so_far, [route, boot(mount, route, so_far, provided, reader, max_body_size)]]
      end
    end
    built = routed.map(&:last)
    return built unless strict

    refused = built.filter_map { |endpoint| untyped(endpoint, reader) }
    raise Skyward::Core::BootError, refused.join("\n") unless refused.empty?

    built
  end

  private

  # @rbs (Skyward::API::_Provider & Object callable) -> Method
  def call_method(callable) = callable.is_a?(Method) ? callable : callable.method(:call)

  # The reader finds a signature only for an instance method of a class.
  # @rbs (Symbol name, Skyward::API::_Provider & Object callable) -> String?
  def single_object(name, callable)
    method = call_method(callable)
    return unless method.receiver.is_a?(Module) || method.owner.singleton_class?

    "The :#{name} provider's `#{method.name}` is defined on a single object, such as a module or a class, " \
      "and Skyward API can't read the signature of those. Provide an instance of a class."
  end

  # @rbs (Symbol name, Skyward::API::_Provider & Object callable, Skyward::Core::Types::Reader reader) ->
  #       Skyward::API::Routing::Router::Provider
  def provider(name, callable, reader)
    label = "The :#{name} provider"
    method = call_method(callable)
    # A method is signed by the module that defines it, which isn't always its receiver's class.
    returned = signature(method.owner, method.name, reader)&.type&.return_type
    if returned.nil? || returned.is_a?(RBS::Types::Bases::Any)
      serializer = Skyward::API::Serializer.new([Skyward::API::Serializer::UNTYPED], label:)
      return Skyward::API::Routing::Router::Provider.new(name:, callable:, value: nil, responses: [], serializer:)
    end

    parts = parts(returned)
    responses = parts.filter_map { |part| response_value(part) }
    value = parts.reject { |part| response_value(part) }
    serializer = Skyward::API::Serializer.new(responses, label:)
    Skyward::API::Routing::Router::Provider.new(name:, callable:, value:, responses:, serializer:)
  end

  # @rbs mount: Skyward::API::Assembly::Builder::Mount
  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs built: Array[[Skyward::API::Endpoints::Route, Skyward::API::Routing::Router::Endpoint]]
  # @rbs providers: Hash[Symbol, Skyward::API::Routing::Router::Provider]
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs max_body_size: Integer
  # @rbs return: Skyward::API::Routing::Router::Endpoint
  def boot(mount, route, built, providers, reader, max_body_size)
    path = full_path(mount.at, route.path)
    verb = route.verb.upcase.name
    pattern = pattern(path)
    label = "#{mount.api.class}##{route.to} (#{verb} #{path})"
    result = summary(route) || shadowing(route, verb, pattern, built) ||
             endpoint(mount.api, route, verb, pattern, label, providers, reader, max_body_size)
    case result
    when Refusal then raise Skyward::Core::BootError, explained(label, result)
    else result
    end
  end

  # Core's own errors carry their excerpt in their message, already indented,
  # so every line but an excerpt's is indented under the label.
  # @rbs label: String
  # @rbs refusal: Refusal
  # @rbs return: String
  def explained(label, refusal)
    excerpt = Skyward::Core::Diagnostics::Excerpt.render(refusal.spots)
    body = [[refusal.problem, excerpt].compact.join("\n\n"), refusal.hint].compact.join("\n")
    lines = body.lines(chomp: true).map do |line|
      line.empty? || line.start_with?(Skyward::Core::Diagnostics::Excerpt::INDENT) ? line : "  #{line}"
    end
    [label, *lines].join("\n")
  end

  # @rbs problem: String
  # @rbs spots: Array[Skyward::Core::Diagnostics::Spot?]
  # @rbs hint: String?
  # @rbs return: Refusal
  def refused(problem, spots: [], hint: nil) = Refusal.new(problem:, spots: spots.compact, hint:)

  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs key: Symbol
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def argument(route, key)
    file = route.file
    line = route.line
    Skyward::Core::Diagnostics::Spots.keyword_value(file, line, call: route.verb, key:) if file && line
  end

  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs part: String
  # @rbs return: Skyward::Core::Diagnostics::Spot?
  def in_path(route, part)
    file = route.file
    line = route.line
    Skyward::Core::Diagnostics::Spots.string(file, line, call: route.verb, part:) if file && line
  end

  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs return: Refusal?
  def summary(route)
    return unless route.summary&.match?(/\R/)

    refused(
      'Its summary: has a line break, but a summary is one line. Put the rest in description:.',
      spots: [argument(route, :summary)]
    )
  end

  # @rbs prefix: String
  # @rbs path: String
  # @rbs return: String
  def full_path(prefix, path)
    parts = [prefix, path].map { |part| part.delete_prefix('/').delete_suffix('/') }
    "/#{parts.reject(&:empty?).join('/')}"
  end

  # @rbs path: String
  # @rbs return: Array[String | Symbol]
  def pattern(path)
    path.split('/', -1).map { |segment| segment.start_with?(':') ? segment.delete_prefix(':').to_sym : segment }
  end

  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs verb: String
  # @rbs pattern: Array[String | Symbol]
  # @rbs built: Array[[Skyward::API::Endpoints::Route, Skyward::API::Routing::Router::Endpoint]]
  # @rbs return: Refusal?
  def shadowing(route, verb, pattern, built)
    found = built.find { |_, endpoint| endpoint.verb == verb && covers?(endpoint.pattern, pattern) }
    return unless found

    earlier_route, earlier = found
    problem =
      if covers?(pattern, earlier.pattern)
        "#{earlier.label} is tried first and matches exactly the same paths, so this route is never reached. " \
          'Remove one of them, or change a path.'
      else
        "#{earlier.label} is tried first and matches every path this route does, so this route is never reached. " \
          'Declare the static route first.'
      end
    refused(problem, spots: [earlier_route, route].map { |declared| in_path(declared, declared.path) })
  end

  # A path parameter matches any segment but an empty one, which only the root path has.
  # @rbs pattern: Array[String | Symbol]
  # @rbs other: Array[String | Symbol]
  # @rbs return: bool
  def covers?(pattern, other)
    pattern.length == other.length &&
      pattern.zip(other).all? { |part, other_part| part == other_part || (part.is_a?(Symbol) && other_part != '') }
  end

  # @rbs api: Skyward::API
  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs verb: String
  # @rbs pattern: Array[String | Symbol]
  # @rbs label: String
  # @rbs providers: Hash[Symbol, Skyward::API::Routing::Router::Provider]
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs max_body_size: Integer
  # @rbs return: Skyward::API::Routing::Router::Endpoint | Refusal
  def endpoint(api, route, verb, pattern, label, providers, reader, max_body_size)
    method_type = method_type(api.class, route, reader)
    return method_type if method_type.is_a?(Refusal)

    method = api.class.instance_method(route.to)
    function = method_type&.type
    signed = signed(method, function)
    return signed if signed.is_a?(Refusal)

    path_parameters = pattern.grep(Symbol) #: Array[Symbol]
    unnamed = path_parameters.find { |name| signed.none? { |keyword, _, _| keyword == name } }
    if unnamed
      query = signed.filter_map { |name, _, _| name if source(name, pattern) == :query && !providers.key?(name) }
      return no_keyword(route, method, unnamed, query)
    end

    both = path_parameters.find { |name| providers.key?(name) }
    if both
      problem = "The route has a path parameter :#{both}, but :#{both} is provided too, so `#{both}:` can't be both. " \
                'Rename the path parameter, or provide another name.'
      return refused(
        problem,
        spots: [in_path(route, ":#{both}"), Skyward::Core::Diagnostics::Spots.keyword_parameter(method, both)]
      )
    end

    read = signed.to_h { |name, required, type| [name, keyword(name, required, type, pattern, providers, reader)] }
    name, problem = read.find { |_, keyword| keyword.is_a?(Refusal) }
    if name && problem.is_a?(Refusal)
      return problem.with(spots: [Skyward::Core::Diagnostics::Spots.keyword_parameter(method, name)].compact)
    end

    keywords = read.values.grep(Skyward::API::Routing::Router::Keyword) #: Array[Skyward::API::Routing::Router::Keyword]
    provided = read.values.grep(Skyward::API::Routing::Router::Provider) #: Array[Skyward::API::Routing::Router::Provider]

    returns = returns(function&.return_type || ANY, reader)
    if returns.is_a?(Refusal)
      return returns.with(spots: [Skyward::Core::Diagnostics::Spots.method_name(method)].compact)
    end

    inputs = Skyward::API::Inputs.new(keywords, providers: provided, max_body_size:)
    serializer = Skyward::API::Serializer.new(returns, label:)
    Skyward::API::Routing::Router::Endpoint.new(
      verb:,
      pattern:,
      api:,
      to: route.to,
      label:,
      summary: route.summary,
      description: route.description,
      keywords:,
      providers: provided,
      returns:,
      signature: written_signature(method_type || unannotated(signed)),
      inputs:,
      serializer:
    )
  # The reader raises for a type it can't read at all, such as one that refers
  # to itself, and that's this route's problem too.
  rescue Skyward::Core::BootError => e
    refused(e.message)
  end

  # @rbs klass: Class
  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: RBS::MethodType | Refusal | nil
  def method_type(klass, route, reader)
    to = route.to
    return signature(klass, to, reader) if klass.public_method_defined?(to)

    refused(
      "#{klass} has no public method `#{to}`. Define it as a public method, or change to:.",
      spots: [argument(route, :to)],
      hint: unrouted(klass, to)
    )
  end

  # Only the class's own methods, so that a method it inherits, as from
  # Skyward::API or Kernel, is never suggested.
  # @rbs klass: Class
  # @rbs to: Symbol
  # @rbs return: String?
  def unrouted(klass, to)
    hidden =
      if klass.private_method_defined?(to, false) then 'private'
      elsif klass.protected_method_defined?(to, false) then 'protected'
      end
    return "#{to} is #{hidden}. Move it above `#{hidden}`." if hidden

    closest = Skyward::Core::Diagnostics::Suggestion.closest(to.to_s, klass.public_instance_methods(false).map(&:to_s))
    "Did you mean to: :#{closest}?" if closest
  end

  # @rbs owner: Module
  # @rbs name: Symbol
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: RBS::MethodType?
  def signature(owner, name, reader)
    type_name = reader.type_name(owner)
    reader.method_type(type_name, name) if type_name
  end

  # @rbs method: UnboundMethod
  # @rbs type: RBS::Types::function?
  # @rbs return: Array[[Symbol, bool, RBS::Types::t]] | Refusal
  def signed(method, type)
    parameters = method.parameters
    if parameters.any? { |kind, _| UNNAMED.include?(kind) }
      return refused(
        'The method takes positional arguments or **rest, but Skyward API passes only named keywords. ' \
        'Take each input as a keyword, such as `id:`.',
        spots: [Skyward::Core::Diagnostics::Spots.parameters(method)]
      )
    end

    keywords = parameters.filter_map { |kind, name| [name, kind == :keyreq] if KEYWORD.include?(kind) }.to_h
    return keywords.map { |name, required| [name, required, ANY] } unless type

    function = keyword_only(type)
    return stale(keywords, type) unless function && keyword_requirements(function) == keywords

    params = function.required_keywords.merge(function.optional_keywords)
    keywords.map { |name, required| [name, required, params.fetch(name).type] }
  end

  # @rbs method_type: RBS::MethodType
  # @rbs return: String
  def written_signature(method_type) = method_type.location&.source || method_type.to_s

  # @rbs signed: Array[[Symbol, bool, RBS::Types::t]]
  # @rbs return: RBS::MethodType
  def unannotated(signed)
    params = signed.to_h { |name, _, type| [name, RBS::Types::Function::Param.new(type:, name: nil)] }
    required = signed.filter_map { |name, needed, _| name if needed }
    function = RBS::Types::Function.empty(ANY).update(
      required_keywords: params.slice(*required),
      optional_keywords: params.except(*required)
    )
    RBS::MethodType.new(type_params: [], type: function, block: nil, location: nil)
  end

  # @rbs keywords: Hash[Symbol, bool]
  # @rbs function: RBS::Types::function
  # @rbs return: Refusal
  def stale(keywords, function)
    taken = keywords.map { |name, required| "#{'?' unless required}#{name}:" }
    refused(
      "The method takes (#{taken.join(', ')}), but its signature takes (#{written(function.param_to_s)}), " \
      'so the signature is stale. Run rbs-inline, or update the signature.'
    )
  end

  # @rbs function: RBS::Types::function
  # @rbs return: RBS::Types::Function?
  def keyword_only(function)
    case function
    when RBS::Types::Function
      others = [
        *function.required_positionals,
        *function.optional_positionals,
        *function.trailing_positionals,
        function.rest_positionals,
        function.rest_keywords
      ]
      function if others.compact.empty?
    end
  end

  # @rbs function: RBS::Types::Function
  # @rbs return: Hash[Symbol, bool]
  def keyword_requirements(function)
    function.required_keywords.transform_values { true }.merge(function.optional_keywords.transform_values { false })
  end

  # @rbs route: Skyward::API::Endpoints::Route
  # @rbs method: UnboundMethod
  # @rbs parameter: Symbol
  # @rbs query: Array[Symbol]
  # @rbs return: Refusal
  def no_keyword(route, method, parameter, query)
    problem = "The route has a path parameter :#{parameter}, but the method has no `#{parameter}:` keyword. " \
              "Add `#{parameter}:` to the method, or rename the path parameter."
    meant = meant(parameter, query)
    keyword = Skyward::Core::Diagnostics::Spots.keyword_parameter(method, meant) if meant
    parameters = Skyward::Core::Diagnostics::Spots.parameters(method)
    hint = rename_hint(method, parameters, keyword, parameter) if parameters && keyword
    refused(problem, spots: [argument(route, :to)&.with(columns: nil), keyword || parameters], hint:)
  end

  # A nested resource's renamed parameter, as `todo_id:` for `/:id`, isn't a
  # misspelling DidYouMean would find, so a keyword that ends in the parameter,
  # or that the parameter ends in, is meant too, when it's the only one.
  # @rbs parameter: Symbol
  # @rbs query: Array[Symbol]
  # @rbs return: Symbol?
  def meant(parameter, query)
    closest = Skyward::Core::Diagnostics::Suggestion.closest(parameter.to_s, query.map(&:to_s))
    return closest.to_sym if closest

    suffixed = query.select { |name| name.end_with?("_#{parameter}") || parameter.end_with?("_#{name}") }
    suffixed.first if suffixed.one?
  end

  # Core's spot of a parameter list that runs onto another line stops at the end
  # of its first, so only a list written whole on the `def` line is rewritten.
  # @rbs method: UnboundMethod
  # @rbs parameters: Skyward::Core::Diagnostics::Spot
  # @rbs keyword: Skyward::Core::Diagnostics::Spot
  # @rbs parameter: Symbol
  # @rbs return: String?
  def rename_hint(method, parameters, keyword, parameter)
    list = parameters.columns
    columns = keyword.columns
    text = parameters.text
    line = method.source_location&.last
    return unless list && columns && parameters.line == line && text[list.end] == ')' && keyword.line == line

    renamed = text[columns].to_s.sub(/\A[^:]+/, parameter.to_s)
    rewritten = "#{text[list.begin...columns.begin]}#{renamed}#{text[columns.end...list.end]}"
    "Did you mean `def #{method.original_name}(#{rewritten})`?"
  end

  # @rbs name: Symbol
  # @rbs required: bool
  # @rbs type: RBS::Types::t
  # @rbs pattern: Array[String | Symbol]
  # @rbs providers: Hash[Symbol, Skyward::API::Routing::Router::Provider]
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: Skyward::API::Routing::Router::Keyword | Skyward::API::Routing::Router::Provider | Refusal
  def keyword(name, required, type, pattern, providers, reader)
    source = source(name, pattern)
    return request(required, type) if source == :request

    provider = providers[name]
    return provided(name, type, provider) if provider

    read = reader.read(type)
    case read
    when Skyward::Core::Types::Unreadable then unreadable("The type of `#{name}:`", read)
    else
      carried(name, source, read) || Skyward::API::Routing::Router::Keyword.new(name:, source:, required:, type: read)
    end
  end

  # @rbs name: Symbol
  # @rbs pattern: Array[String | Symbol]
  # @rbs return: :path | :query | :body | :request
  def source(name, pattern)
    if pattern.include?(name) then :path
    elsif name == :body then :body
    elsif name == :request then :request
    else :query
    end
  end

  # @rbs required: bool
  # @rbs type: RBS::Types::t
  # @rbs return: Skyward::API::Routing::Router::Keyword | Refusal
  def request(required, type)
    unless [REQUEST, ANY].include?(type)
      return refused(
        '`request:` is always the Skyward::API::Request, but its signature types it as ' \
        "#{written(type.to_s)}. Type it as Skyward::API::Request, or rename the keyword."
      )
    end

    Skyward::API::Routing::Router::Keyword.new(name: :request, source: :request, required:, type: REQUEST_TYPE)
  end

  # A provided keyword's type is the provider's to give, so it's compared, never
  # read, except that an untyped keyword is left unchecked, as untyped code is.
  # @rbs name: Symbol
  # @rbs type: RBS::Types::t
  # @rbs provider: Skyward::API::Routing::Router::Provider
  # @rbs return: Skyward::API::Routing::Router::Provider | Refusal
  def provided(name, type, provider)
    value = provider.value
    return provider if value.nil? || untyped_type?(type) || same?(parts(type), value)

    returned = value.empty? ? 'only responses' : "#{written(value.join(' | '))}, besides any responses"
    refused(
      "`#{name}:` is typed as #{written(type.to_s)}, but the :#{name} provider returns #{returned}. " \
      'Give them the same type.'
    )
  end

  # @rbs type: RBS::Types::t
  # @rbs return: bool
  def untyped_type?(type) = parts(type).grep_v(RBS::Types::Bases::Nil) == [ANY]

  # A union means the same in any order.
  # @rbs types: Array[RBS::Types::t]
  # @rbs others: Array[RBS::Types::t]
  # @rbs return: bool
  def same?(types, others) = (types - others).empty? && (others - types).empty?

  # @rbs name: Symbol
  # @rbs source: :path | :query | :body | :request
  # @rbs type: Skyward::Core::Types::t
  # @rbs return: Refusal?
  def carried(name, source, type)
    case source
    when :path
      uncarried = uncarried(type, :path)
      if uncarried
        refused(
          "`#{name}:` comes from the path, which can't carry #{uncarried}. " \
          'Give it a type such as String, Integer or an enum.'
        )
      end
    when :query
      uncarried = uncarried(type, :query)
      if uncarried
        refused(
          "`#{name}:` comes from the query string, which can't carry #{uncarried}. " \
          'Give it a type such as String, Integer or an array of them, or take it in `body:`.'
        )
      end
    end
  end

  # @rbs type: Skyward::Core::Types::t
  # @rbs within: :path | :query | :array
  # @rbs return: String?
  def uncarried(type, within)
    case type
    when Skyward::Core::Types::Record then 'a record'
    when Skyward::Core::Types::HashOf then 'a hash'
    when Skyward::Core::Types::Named then "#{type.name}, a class"
    when Skyward::Core::Types::ArrayOf
      case within
      when :path then 'an array'
      when :query then uncarried(type.type, :array)
      else 'an array of arrays'
      end
    when Skyward::Core::Types::Nullable then uncarried(type.type, within)
    when Skyward::Core::Types::Union then type.types.lazy.filter_map { |member| uncarried(member, within) }.first
    end
  end

  # Response values are found in the signature, because the reader can't read them.
  # @rbs type: RBS::Types::t
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: Array[Skyward::API::Routing::Router::returned] | Refusal
  def returns(type, reader)
    read = parts(type).map { |part| response(part, reader) || reader.read(part) }
    unreadable = read.find { |member| member.is_a?(Skyward::Core::Types::Unreadable) }
    return unreadable('The return type', unreadable) if unreadable.is_a?(Skyward::Core::Types::Unreadable)

    readable = read.grep_v(Skyward::Core::Types::Unreadable) #: Array[Skyward::API::Routing::Router::returned]
    readable.flat_map { |member| members(member) }.uniq
  end

  # @rbs type: RBS::Types::t
  # @rbs return: Array[RBS::Types::t]
  def parts(type)
    case type
    when RBS::Types::Union then type.types.flat_map { |member| parts(member) }
    when RBS::Types::Optional then [*parts(type.type), RBS::Types::Bases::Nil.new(location: nil)]
    else [type]
    end
  end

  # @rbs type: RBS::Types::t
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: Skyward::API::Routing::Router::Created | Skyward::API::Routing::Router::Response | Skyward::API::Routing::Router::Rack
  #   | Skyward::Core::Types::Unreadable | nil
  def response(type, reader)
    return Skyward::API::Routing::Router::Rack.new if RACK.include?(type)
    if type.is_a?(RBS::Types::ClassInstance) && type.name.to_s == '::Skyward::API::Responses::Created'
      return created(type, reader)
    end

    response_value(type)
  end

  # @rbs type: RBS::Types::t
  # @rbs return: Skyward::API::Routing::Router::Response?
  def response_value(type)
    return unless type.is_a?(RBS::Types::ClassInstance)

    klass = Skyward::API::Serializer::RESPONSES.find { |response| type.name.to_s == "::#{response.name}" }
    Skyward::API::Routing::Router::Response.new(klass:) if klass
  end

  # @rbs type: RBS::Types::ClassInstance
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: Skyward::API::Routing::Router::Created | Skyward::Core::Types::Unreadable
  def created(type, reader)
    unless type.args.size == 1
      instead = 'Skyward::API::Responses::Created[T]'
      return Skyward::Core::Types::Unreadable.new(type: written(type.to_s), at: nil, instead:, suggestion: nil)
    end

    read = reader.read(type.args.fetch(0))
    case read
    when Skyward::Core::Types::Unreadable then read
    else Skyward::API::Routing::Router::Created.new(type: read)
    end
  end

  # @rbs type: Skyward::API::Routing::Router::returned
  # @rbs return: Array[Skyward::API::Routing::Router::returned]
  def members(type)
    case type
    when Skyward::Core::Types::Union then type.types
    when Skyward::Core::Types::Nullable then [*members(type.type), Skyward::Core::Types::Reader::NIL_LITERAL]
    else [type]
    end
  end

  # @rbs endpoint: Skyward::API::Routing::Router::Endpoint
  # @rbs reader: Skyward::Core::Types::Reader
  # @rbs return: String?
  def untyped(endpoint, reader)
    method_type = signature(endpoint.api.class, endpoint.to, reader)
    function = keyword_only(method_type.type) if method_type
    problem =
      if function
        untyped_parts(endpoint, function)
      else
        'It has no RBS signature, but strict: true refuses an untyped endpoint. ' \
          'Annotate it and run rbs-inline, or check `signatures:`.'
      end
    "#{endpoint.label}\n  #{problem}" if problem
  end

  # Only a keyword's whole type, nullable or not, or a member of the return type
  # counts, so strict: true lets through untyped inside a type, as in Array[untyped].
  # @rbs endpoint: Skyward::API::Routing::Router::Endpoint
  # @rbs function: RBS::Types::Function
  # @rbs return: String?
  def untyped_parts(endpoint, function)
    any = Skyward::API::Serializer::UNTYPED
    keywords = endpoint.keywords.filter_map do |keyword|
      type = keyword.type
      "`#{keyword.name}:`" if (type.is_a?(Skyward::Core::Types::Nullable) ? type.type : type) == any
    end
    # A provided keyword's type is never read, so it's found in the signature.
    params = function.required_keywords.merge(function.optional_keywords)
    provided = endpoint.providers.filter_map do |provider|
      "`#{provider.name}:`" if untyped_type?(params.fetch(provider.name).type)
    end
    named = [*keywords, *provided]
    found = endpoint.returns.include?(any) ? [*named, 'the return type'] : named
    return if found.empty?

    *rest, last = found
    listed = rest.empty? ? last : "#{rest.join(', ')} and #{last}"
    "Its signature leaves #{listed} untyped, but strict: true refuses an untyped endpoint. " \
      "Give #{found.one? ? 'it' : 'each'} a type."
  end

  # @rbs subject: String
  # @rbs type: Skyward::Core::Types::Unreadable
  # @rbs return: Refusal
  def unreadable(subject, type)
    suggestion = type.suggestion
    refused(
      "#{subject} can't be read: Skyward API doesn't read #{type.type}#{", at #{type.at}" if type.at}. " \
      "Use #{type.instead} instead.",
      hint: ("Did you mean #{suggestion}?" if suggestion)
    )
  end

  # @rbs text: String
  # @rbs return: String
  def written(text) = text.gsub(/(?<!\w)::/, '')
end
