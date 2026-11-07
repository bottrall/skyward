# frozen_string_literal: true

module Skyward::API::Boot
  extend self

  UNNAMED = %i[req opt rest keyrest].freeze #: Array[Symbol]

  KEYWORD = %i[keyreq key].freeze #: Array[Symbol]

  # @rbs mounts: Array[Skyward::API::Builder::Mount]
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: Array[Skyward::API::Router::Endpoint]
  def endpoints(mounts, reader:)
    none = [] #: Array[[String, Skyward::API::Router::Endpoint]]
    booted = mounts.reduce(none) do |built, mount|
      mount.api.class.routes.reduce(built) { |so_far, route| [*so_far, boot(mount, route, so_far, reader)] }
    end
    booted.map(&:last)
  end

  private

  # @rbs mount: Skyward::API::Builder::Mount
  # @rbs route: Skyward::API::Route
  # @rbs built: Array[[String, Skyward::API::Router::Endpoint]]
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: [String, Skyward::API::Router::Endpoint]
  def boot(mount, route, built, reader)
    path = full_path(mount.at, route.path)
    verb = route.verb.upcase.name
    pattern = pattern(path)
    label = "#{mount.api.class}##{route.to} (#{verb} #{path})"
    result = summary(route) || shadowing(verb, pattern, built) ||
             endpoint(mount.api, route, verb, pattern, label, reader)
    case result
    when String then raise Skyward::BootError, "#{label}\n  #{result}"
    else [label, result]
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
  # @rbs built: Array[[String, Skyward::API::Router::Endpoint]]
  # @rbs return: String?
  def shadowing(verb, pattern, built)
    label, earlier = built.find { |_, endpoint| endpoint.verb == verb && covers?(endpoint.pattern, pattern) }
    return unless earlier

    if covers?(pattern, earlier.pattern)
      "#{label} is tried first and matches exactly the same paths, so this route is never reached. " \
        "Remove one of them, or change a path."
    else
      "#{label} is tried first and matches every path this route does, so this route is never reached. " \
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
  # @rbs return: Skyward::API::Router::Endpoint | String
  def endpoint(api, route, verb, pattern, label, reader)
    method_type = method_type(api.class, route.to, reader)
    return method_type if method_type.is_a?(String)

    signed = signed(api.class.instance_method(route.to).parameters, method_type)
    return signed if signed.is_a?(String)

    unnamed = pattern.grep(Symbol).find { |name| signed.none? { |keyword, _, _| keyword == name } }
    if unnamed
      return "The route has a path parameter :#{unnamed}, but the method has no `#{unnamed}:` keyword. " \
             "Add `#{unnamed}:` to the method, or rename the path parameter."
    end

    read = signed.map { |name, required, type| keyword(name, required, reader.read(type), pattern) }
    problem = read.find { |keyword| keyword.is_a?(String) }
    return problem if problem.is_a?(String)

    keywords = read.grep(Skyward::API::Router::Keyword) #: Array[Skyward::API::Router::Keyword]

    returns = returns(method_type.type.return_type, reader)
    return returns if returns.is_a?(String)

    serializer = Skyward::API::Serializer.new(returns, label:)
    Skyward::API::Router::Endpoint.new(verb:, pattern:, api:, to: route.to, keywords:, returns:, serializer:)
  # The reader raises for a type it can't read at all, such as one that refers
  # to itself, and that's this route's problem too.
  rescue Skyward::BootError => e
    e.message
  end

  # @rbs klass: Class
  # @rbs to: Symbol
  # @rbs reader: Skyward::Types::Reader
  # @rbs return: RBS::MethodType | String
  def method_type(klass, to, reader)
    unless klass.public_method_defined?(to)
      return "#{klass} has no public method `#{to}`. Define it as a public method, or change to:."
    end

    type_name = reader.type_name(klass)
    method_type = reader.method_type(type_name, to) if type_name
    method_type || "#{klass}##{to} has no RBS signature. Run rbs-inline, or check `signatures:`."
  end

  # @rbs parameters: Method::param_types
  # @rbs method_type: RBS::MethodType
  # @rbs return: Array[[Symbol, bool, RBS::Types::t]] | String
  def signed(parameters, method_type)
    if parameters.any? { |kind, _| UNNAMED.include?(kind) }
      return "The method takes positional arguments or **rest, but Skyward API passes only named keywords. " \
             "Take each input as a keyword, such as `id:`."
    end

    keywords = parameters.filter_map { |kind, name| [name, kind == :keyreq] if KEYWORD.include?(kind) }.to_h
    function = keyword_only(method_type.type)
    return stale(keywords, method_type.type) unless function && keyword_requirements(function) == keywords

    params = function.required_keywords.merge(function.optional_keywords)
    keywords.map { |name, required| [name, required, params.fetch(name).type] }
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
  # @rbs type: Skyward::Types::result
  # @rbs pattern: Array[String | Symbol]
  # @rbs return: Skyward::API::Router::Keyword | String
  def keyword(name, required, type, pattern)
    case type
    when Skyward::Types::Unreadable then unreadable("The type of `#{name}:`", type)
    else
      source = source(name, pattern)
      carried(name, source, type) || Skyward::API::Router::Keyword.new(name:, source:, required:, type:)
    end
  end

  # @rbs name: Symbol
  # @rbs pattern: Array[String | Symbol]
  # @rbs return: :path | :query | :body
  def source(name, pattern)
    if pattern.include?(name) then :path
    elsif name == :body then :body
    else :query
    end
  end

  # @rbs name: Symbol
  # @rbs source: :path | :query | :body
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
  # @rbs return: Skyward::API::Router::Created | Skyward::API::Router::Response | Skyward::Types::Unreadable | nil
  def response(type, reader)
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
