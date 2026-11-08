# frozen_string_literal: true

module Skyward::API::Boot
  extend self

  UNNAMED = %i[req opt rest keyrest].freeze #: Array[Symbol]

  KEYWORD = %i[keyreq key].freeze #: Array[Symbol]

  RACK = ["::Skyward::rack", "[::Integer, ::Hash[::String, ::String], untyped]"].map do |type|
    RBS::Parser.parse_type(type)
  end.freeze #: Array[RBS::Types::t?]

  REQUEST = RBS::Parser.parse_type("::Skyward::Request") #: RBS::Types::t?

  REQUEST_TYPE = Skyward::Types::Named.new(name: "Skyward::Request", klass: Skyward::Request, fields: []) #: Skyward::Types::Named

  # A method with no signature is read as if each keyword and the return were
  # untyped, which is what rbs-inline writes for a method with no annotations.
  ANY = RBS::Types::Bases::Any.new(location: nil) #: RBS::Types::Bases::Any

  # @rbs mounts: Array[Skyward::API::Builder::Mount]
  # @rbs reader: Skyward::Types::Reader
  # @rbs max_body_size: Integer
  # @rbs strict: bool
  # @rbs return: Array[Skyward::API::Router::Endpoint]
  def endpoints(mounts, reader:, max_body_size:, strict:)
    none = [] #: Array[Skyward::API::Router::Endpoint]
    built = mounts.reduce(none) do |booted, mount|
      mount.api.class.routes.reduce(booted) do |so_far, route|
        [*so_far, boot(mount, route, so_far, reader, max_body_size)]
      end
    end
    return built unless strict

    refused = built.filter_map { |endpoint| untyped(endpoint, reader) }
    raise Skyward::BootError, refused.join("\n") unless refused.empty?

    built
  end

  private

  # @rbs mount: Skyward::API::Builder::Mount
  # @rbs route: Skyward::API::Route
  # @rbs built: Array[Skyward::API::Router::Endpoint]
  # @rbs reader: Skyward::Types::Reader
  # @rbs max_body_size: Integer
  # @rbs return: Skyward::API::Router::Endpoint
  def boot(mount, route, built, reader, max_body_size)
    path = full_path(mount.at, route.path)
    verb = route.verb.upcase.name
    pattern = pattern(path)
    label = "#{mount.api.class}##{route.to} (#{verb} #{path})"
    result = summary(route) || shadowing(verb, pattern, built) ||
             endpoint(mount.api, route, verb, pattern, label, reader, max_body_size)
    case result
    when String then raise Skyward::BootError, "#{label}\n  #{result}"
    else result
    end
  end

  # @rbs route: Skyward::API::Route
  # @rbs return: String?
  def summary(route)
    return unless route.summary&.match?(/\R/)

    "Its summary: has a line break, but a summary is one line. Put the rest in description:."
  end

  # @rbs prefix: String
  # @rbs path: String
  # @rbs return: String
  def full_path(prefix, path)
    parts = [prefix, path].map { |part| part.delete_prefix("/").delete_suffix("/") }
    "/#{parts.reject(&:empty?).join("/")}"
  end

  # @rbs path: String
  # @rbs return: Array[String | Symbol]
  def pattern(path)
    path.split("/", -1).map { |segment| segment.start_with?(":") ? segment.delete_prefix(":").to_sym : segment }
  end

  # @rbs verb: String
  # @rbs pattern: Array[String | Symbol]
  # @rbs built: Array[Skyward::API::Router::Endpoint]
  # @rbs return: String?
  def shadowing(verb, pattern, built)
    earlier = built.find { |endpoint| endpoint.verb == verb && covers?(endpoint.pattern, pattern) }
    return unless earlier

    if covers?(pattern, earlier.pattern)
      "#{earlier.label} is tried first and matches exactly the same paths, so this route is never reached. " \
        "Remove one of them, or change a path."
    else
      "#{earlier.label} is tried first and matches every path this route does, so this route is never reached. " \
        "Declare the static route first."
    end
  end

  # A path parameter matches any segment but an empty one, which only the root path has.
  # @rbs pattern: Array[String | Symbol]
  # @rbs other: Array[String | Symbol]
  # @rbs return: bool
  def covers?(pattern, other)
    pattern.length == other.length &&
      pattern.zip(other).all? { |part, other_part| part == other_part || (part.is_a?(Symbol) && other_part != "") }
  end

  # @rbs api: Skyward::API
  # @rbs route: Skyward::API::Route
  # @rbs verb: String
  # @rbs pattern: Array[String | Symbol]
  # @rbs label: String
  # @rbs reader: Skyward::Types::Reader
  # @rbs max_body_size: Integer
  # @rbs return: Skyward::API::Router::Endpoint | String
  def endpoint(api, route, verb, pattern, label, reader, max_body_size)
    method_type = method_type(api.class, route.to, reader)
    return method_type if method_type.is_a?(String)

    function = method_type&.type
    signed = signed(api.class.instance_method(route.to).parameters, function)
    return signed if signed.is_a?(String)

    unnamed = pattern.grep(Symbol).find { |name| signed.none? { |keyword, _, _| keyword == name } }
    if unnamed
      return "The route has a path parameter :#{unnamed}, but the method has no `#{unnamed}:` keyword. " \
             "Add `#{unnamed}:` to the method, or rename the path parameter."
    end

    read = signed.map { |name, required, type| keyword(name, required, type, pattern, reader) }
    problem = read.find { |keyword| keyword.is_a?(String) }
    return problem if problem.is_a?(String)

    keywords = read.grep(Skyward::API::Router::Keyword) #: Array[Skyward::API::Router::Keyword]

    returns = returns(function&.return_type || ANY, reader)
    return returns if returns.is_a?(String)

    inputs = Skyward::API::Inputs.new(keywords, max_body_size:)
    serializer = Skyward::API::Serializer.new(returns, label:)
    Skyward::API::Router::Endpoint.new(
      verb:,
      pattern:,
      api:,
      to: route.to,
      label:,
      summary: route.summary,
      description: route.description,
      keywords:,
      returns:,
      signature: written_signature(method_type || unannotated(signed)),
      inputs:,
      serializer:
    )
  # The reader raises for a type it can't read at all, such as one that refers
  # to itself, and that's this route's problem too.
  rescue Skyward::BootError => e
    e.message
  end

  # @rbs klass: Class
  # @rbs to: Symbol
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: RBS::MethodType | String | nil
  def method_type(klass, to, reader)
    unless klass.public_method_defined?(to)
      return "#{klass} has no public method `#{to}`. Define it as a public method, or change to:."
    end

    signature(klass, to, reader)
  end

  # @rbs klass: Class
  # @rbs to: Symbol
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: RBS::MethodType?
  def signature(klass, to, reader)
    type_name = reader.type_name(klass)
    reader.method_type(type_name, to) if type_name
  end

  # @rbs parameters: Method::param_types
  # @rbs type: RBS::Types::function?
  # @rbs return: Array[[Symbol, bool, RBS::Types::t]] | String
  def signed(parameters, type)
    if parameters.any? { |kind, _| UNNAMED.include?(kind) }
      return "The method takes positional arguments or **rest, but Skyward API passes only named keywords. " \
             "Take each input as a keyword, such as `id:`."
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
  # @rbs return: String
  def stale(keywords, function)
    taken = keywords.map { |name, required| "#{"?" unless required}#{name}:" }
    "The method takes (#{taken.join(", ")}), but its signature takes (#{written(function.param_to_s)}), " \
      "so the signature is stale. Run rbs-inline, or update the signature."
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

  # @rbs name: Symbol
  # @rbs required: bool
  # @rbs type: RBS::Types::t
  # @rbs pattern: Array[String | Symbol]
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: Skyward::API::Router::Keyword | String
  def keyword(name, required, type, pattern, reader)
    source = source(name, pattern)
    return request(required, type) if source == :request

    read = reader.read(type)
    case read
    when Skyward::Types::Unreadable then unreadable("The type of `#{name}:`", read)
    else carried(name, source, read) || Skyward::API::Router::Keyword.new(name:, source:, required:, type: read)
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
  # @rbs return: Skyward::API::Router::Keyword | String
  def request(required, type)
    unless [REQUEST, ANY].include?(type)
      return "`request:` is always the Skyward::Request, but its signature types it as #{written(type.to_s)}. " \
             "Type it as Skyward::Request, or rename the keyword."
    end

    Skyward::API::Router::Keyword.new(name: :request, source: :request, required:, type: REQUEST_TYPE)
  end

  # @rbs name: Symbol
  # @rbs source: :path | :query | :body | :request
  # @rbs type: Skyward::Types::t
  # @rbs return: String?
  def carried(name, source, type)
    case source
    when :path
      uncarried = uncarried(type, :path)
      if uncarried
        "`#{name}:` comes from the path, which can't carry #{uncarried}. " \
          "Give it a type such as String, Integer or an enum."
      end
    when :query
      uncarried = uncarried(type, :query)
      if uncarried
        "`#{name}:` comes from the query string, which can't carry #{uncarried}. " \
          "Give it a type such as String, Integer or an array of them, or take it in `body:`."
      end
    end
  end

  # @rbs type: Skyward::Types::t
  # @rbs within: :path | :query | :array
  # @rbs return: String?
  def uncarried(type, within)
    case type
    when Skyward::Types::Record then "a record"
    when Skyward::Types::HashOf then "a hash"
    when Skyward::Types::Named then "#{type.name}, a class"
    when Skyward::Types::ArrayOf
      case within
      when :path then "an array"
      when :query then uncarried(type.type, :array)
      else "an array of arrays"
      end
    when Skyward::Types::Nullable then uncarried(type.type, within)
    when Skyward::Types::Union then type.types.lazy.filter_map { |member| uncarried(member, within) }.first
    end
  end

  # Response values are found in the signature, because the reader can't read them.
  # @rbs type: RBS::Types::t
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: Array[Skyward::API::Router::returned] | String
  def returns(type, reader)
    read = parts(type).map { |part| response(part, reader) || reader.read(part) }
    unreadable = read.find { |member| member.is_a?(Skyward::Types::Unreadable) }
    return unreadable("The return type", unreadable) if unreadable.is_a?(Skyward::Types::Unreadable)

    readable = read.grep_v(Skyward::Types::Unreadable) #: Array[Skyward::API::Router::returned]
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
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: Skyward::API::Router::Created | Skyward::API::Router::Response | Skyward::API::Router::Rack
  #   | Skyward::Types::Unreadable | nil
  def response(type, reader)
    return Skyward::API::Router::Rack.new if RACK.include?(type)
    return unless type.is_a?(RBS::Types::ClassInstance)

    name = type.name.to_s
    return created(type, reader) if name == "::Skyward::Created"

    klass = Skyward::API::Serializer::RESPONSES.find { |response| name == "::#{response.name}" }
    Skyward::API::Router::Response.new(klass:) if klass
  end

  # @rbs type: RBS::Types::ClassInstance
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: Skyward::API::Router::Created | Skyward::Types::Unreadable
  def created(type, reader)
    unless type.args.size == 1
      return Skyward::Types::Unreadable.new(type: written(type.to_s), at: nil, instead: "Created[T]")
    end

    read = reader.read(type.args.fetch(0))
    case read
    when Skyward::Types::Unreadable then read
    else Skyward::API::Router::Created.new(type: read)
    end
  end

  # @rbs type: Skyward::API::Router::returned
  # @rbs return: Array[Skyward::API::Router::returned]
  def members(type)
    case type
    when Skyward::Types::Union then type.types
    when Skyward::Types::Nullable then [*members(type.type), Skyward::Types::Reader::NIL_LITERAL]
    else [type]
    end
  end

  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: String?
  def untyped(endpoint, reader)
    problem =
      if signature(endpoint.api.class, endpoint.to, reader)
        untyped_parts(endpoint)
      else
        "It has no RBS signature, but strict: true refuses an untyped endpoint. " \
          "Annotate it and run rbs-inline, or check `signatures:`."
      end
    "#{endpoint.label}\n  #{problem}" if problem
  end

  # Only a keyword's whole type, nullable or not, or a member of the return type
  # counts, so strict: true lets through untyped inside a type, as in Array[untyped].
  # @rbs endpoint: Skyward::API::Router::Endpoint
  # @rbs return: String?
  def untyped_parts(endpoint)
    any = Skyward::API::Serializer::UNTYPED
    keywords = endpoint.keywords.filter_map do |keyword|
      type = keyword.type
      "`#{keyword.name}:`" if (type.is_a?(Skyward::Types::Nullable) ? type.type : type) == any
    end
    parts = endpoint.returns.include?(any) ? [*keywords, "the return type"] : keywords
    return if parts.empty?

    *rest, last = parts
    listed = rest.empty? ? last : "#{rest.join(", ")} and #{last}"
    "Its signature leaves #{listed} untyped, but strict: true refuses an untyped endpoint. " \
      "Give #{parts.one? ? "it" : "each"} a type."
  end

  # @rbs subject: String
  # @rbs type: Skyward::Types::Unreadable
  # @rbs return: String
  def unreadable(subject, type)
    "#{subject} can't be read: Skyward API doesn't read #{type.type}#{", at #{type.at}" if type.at}. " \
      "Use #{type.instead} instead."
  end

  # @rbs text: String
  # @rbs return: String
  def written(text) = text.gsub(/(?<!\w)::/, "")
end
