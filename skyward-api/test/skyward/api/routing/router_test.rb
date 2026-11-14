# frozen_string_literal: true

require 'test_helper'

describe Skyward::API::Routing::Router do
  let(:todos) { Class.new(Skyward::API).new }
  let(:inputs) { Skyward::API::Inputs.new([], providers: [], max_body_size: 10) }
  let(:serializer) { Skyward::API::Serializer.new([], label: 'Todos') }

  def endpoint(verb, pattern, to, api: todos)
    Skyward::API::Routing::Router::Endpoint.new(
      verb:,
      pattern:,
      api:,
      to:,
      label: "Todos##{to}",
      summary: nil,
      description: nil,
      keywords: [],
      providers: [],
      returns: [],
      signature: '() -> untyped',
      inputs:,
      serializer:
    )
  end

  let(:router) do
    Skyward::API::Routing::Router.new(
      [
        endpoint('GET', ['', 'todos'], :index),
        endpoint('GET', ['', 'todos', :id], :show),
        endpoint('POST', ['', 'todos', :id, 'complete'], :complete)
      ]
    )
  end

  def found(to, api: todos, **params)
    Skyward::API::Routing::Router::Match.new(api:, to:, inputs:, params:, serializer:)
  end

  describe '#match' do
    it 'matches a route by its method and path' do
      assert_equal found(:complete, id: '42'), router.match('POST', '/todos/42/complete')
    end

    it 'matches a root route' do
      routes = Skyward::API::Routing::Router.new([endpoint('GET', ['', ''], :index)])

      assert_equal found(:index), routes.match('GET', '/')
    end

    it 'matches HEAD to a GET route' do
      assert_equal found(:show, id: '42'), router.match('HEAD', '/todos/42')
    end

    it "doesn't match a method no route has" do
      assert_nil router.match('TRACE', '/todos/42')
    end

    it "doesn't match another method" do
      assert_nil router.match('DELETE', '/todos/42')
    end

    it 'tries endpoints in order' do
      other = Class.new(Skyward::API).new
      routes = Skyward::API::Routing::Router.new(
        [endpoint('GET', ['', :id], :show), endpoint('GET', ['', 'new'], :new_form, api: other)]
      )

      assert_equal found(:show, id: 'new'), routes.match('GET', '/new')
    end

    it 'answers a partial overlap with the parameter route declared first' do
      routes = Skyward::API::Routing::Router.new(
        [endpoint('GET', ['', :slug, 'edit'], :edit), endpoint('GET', ['', 'posts', :id], :show)]
      )

      assert_equal found(:edit, slug: 'posts'), routes.match('GET', '/posts/edit')
    end

    it 'answers a partial overlap with the literal route declared first' do
      routes = Skyward::API::Routing::Router.new(
        [endpoint('GET', ['', 'posts', :id], :show), endpoint('GET', ['', :slug, 'edit'], :edit)]
      )

      assert_equal found(:show, id: 'edit'), routes.match('GET', '/posts/edit')
    end

    it 'answers two routes of the same shape with the first' do
      routes = Skyward::API::Routing::Router.new(
        [endpoint('GET', ['', 'todos', :id], :show), endpoint('GET', ['', 'todos', :slug], :find)]
      )

      assert_equal found(:show, id: '42'), routes.match('GET', '/todos/42')
    end

    it 'answers with the first route though a later one shares a branch with an earlier, longer route' do
      routes = Skyward::API::Routing::Router.new(
        [
          endpoint('GET', ['', :list, 'todos', 'done'], :done),
          endpoint('GET', ['', 'inbox', 'todos'], :inbox),
          endpoint('GET', ['', :list, 'todos'], :index)
        ]
      )

      assert_equal found(:inbox), routes.match('GET', '/inbox/todos')
    end

    it "doesn't match an empty path" do
      assert_nil router.match('GET', '')
    end

    it "doesn't match a path without a leading slash" do
      assert_nil router.match('GET', 'todos/42')
    end

    it "doesn't match a path with a trailing slash the route doesn't have" do
      assert_nil router.match('GET', '/todos/')
    end

    it "doesn't match a path with more segments" do
      assert_nil router.match('GET', '/todos/42/complete')
    end

    it "doesn't match another literal segment" do
      assert_nil router.match('POST', '/todos/42/undo')
    end

    it "doesn't match an empty segment to a path parameter" do
      assert_nil router.match('POST', '/todos//complete')
    end

    it 'percent-decodes a path parameter, keeping %2F inside it' do
      assert_equal found(:show, id: 'a/b c'), router.match('GET', '/todos/a%2Fb%20c')
    end

    it 'matches a percent-encoded literal segment to a path parameter, not the literal' do
      routes = Skyward::API::Routing::Router.new(
        [endpoint('GET', ['', 'todos', 'new'], :new_form), endpoint('GET', ['', 'todos', :id], :show)]
      )

      assert_equal found(:show, id: 'new'), routes.match('GET', '/todos/%6Eew')
    end
  end

  describe '#allowed' do
    it 'lists the methods of every route matching the path, in order, with HEAD for GET and OPTIONS' do
      routes = Skyward::API::Routing::Router.new(
        [
          endpoint('DELETE', ['', 'todos', :id], :destroy),
          endpoint('PUT', ['', 'todos', :id], :replace),
          endpoint('GET', ['', 'todos', 'new'], :new_form),
          endpoint('GET', ['', 'todos', :id], :show)
        ]
      )

      assert_equal %w[GET HEAD PUT DELETE OPTIONS], routes.allowed('/todos/new')
    end

    it 'lists nothing for a path no route matches' do
      assert_empty router.allowed('/todos/42/undo')
    end

    it 'lists HEAD only for a path with a GET route' do
      assert_equal %w[POST OPTIONS], router.allowed('/todos/42/complete')
    end

    it "lists the methods of a path a request of another method didn't match" do
      assert_equal %w[GET HEAD OPTIONS], router.allowed('/todos/42')
    end
  end

  describe 'compared with a scan of every endpoint' do
    def scan_params(pattern, segments)
      return unless pattern.length == segments.length

      pairs = segments.zip(pattern)
      return unless pairs.all? { |segment, part| part.is_a?(Symbol) ? !segment.empty? : segment == part }

      pairs.filter_map do |segment, part|
        [part, Skyward::API::Routing::PercentEncoding.decode(segment)] if part.is_a?(Symbol)
      end.to_h
    end

    def scan_match(endpoints, verb, path)
      segments = path.split('/', -1)
      routed = verb == 'HEAD' ? 'GET' : verb
      endpoints.lazy.filter_map do |endpoint|
        params = scan_params(endpoint.pattern, segments) if endpoint.verb == routed
        found(endpoint.to, **params) if params
      end.first
    end

    def scan_allowed(endpoints, path)
      segments = path.split('/', -1)
      verbs = endpoints.filter_map { |endpoint| endpoint.verb if scan_params(endpoint.pattern, segments) }
      return [] if verbs.empty?

      implied = verbs.include?('GET') ? %w[HEAD OPTIONS] : %w[OPTIONS]
      Skyward::API::Routing::Router::METHODS & (verbs + implied)
    end

    def sequences(parts, lengths)
      lengths.flat_map { |length| parts.repeated_permutation(length).to_a }
    end

    let(:patterns) do
      sequences(['a', 'b', :param], 1..3).map do |parts|
        ['', *parts.each_with_index.map { |part, position| part == :param ? :"p#{position}" : part }]
      end
    end

    let(:declared) do
      patterns.each_with_index.flat_map do |pattern, index|
        deleted = endpoint('DELETE', pattern, :"delete#{index}") if (index % 3).zero?
        [endpoint('GET', pattern, :"get#{index}"), deleted].compact
      end
    end

    let(:paths) do
      joined = sequences(['a', 'b', 'c', ''], 1..3).map { |segments| segments.join('/') }
      joined.flat_map { |path| ["/#{path}", path] }.uniq
    end

    let(:requests) { %w[GET HEAD POST DELETE].product(paths) }

    { 'in declaration order' => :itself, 'in reverse' => :reverse }.each do |order, arrange|
      it "matches what the scan matches, with the endpoints #{order}" do
        endpoints = declared.public_send(arrange)
        routes = Skyward::API::Routing::Router.new(endpoints)

        assert_equal(
          requests.map { |verb, path| scan_match(endpoints, verb, path) },
          requests.map { |verb, path| routes.match(verb, path) }
        )
      end

      it "allows what the scan allows, with the endpoints #{order}" do
        endpoints = declared.public_send(arrange)
        routes = Skyward::API::Routing::Router.new(endpoints)

        assert_equal(paths.map { |path| scan_allowed(endpoints, path) }, paths.map { |path| routes.allowed(path) })
      end
    end
  end
end
