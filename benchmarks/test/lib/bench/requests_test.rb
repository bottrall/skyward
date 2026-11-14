# frozen_string_literal: true

require 'test_helper'

describe Bench::Requests do
  requests = Bench::Requests

  describe '.scenarios' do
    let(:scenarios) { requests.scenarios }

    it "names the API's scenarios" do
      assert_equal %w[api.get api.post api.not_found api.routes.first api.routes.last api.routes.not_found],
                   scenarios.map(&:name)
    end

    it "gets each scenario's expected answer from the app" do
      assert_equal(scenarios.map(&:expected), scenarios.map { |scenario| scenario.answer.call(scenario.run.call) })
    end

    it 'reports each in requests' do
      assert_equal [['requests', 1]], scenarios.map { |scenario| [scenario.unit, scenario.per_iteration] }.uniq
    end
  end

  describe '.scenario' do
    let(:app) { ->(_env) { [404, {}, ['{"title":"Not Found","status":404}']] } }

    it "answers the status and the body's expected fields" do
      scenario = requests.scenario('x', app, 'GET', '/', { status: 404, title: 'Not Found' })

      assert_equal({ status: 404, title: 'Not Found' }, scenario.answer.call(scenario.run.call))
    end

    it "answers nil for an expected field the body doesn't have" do
      scenario = requests.scenario('x', app, 'GET', '/', { status: 200, id: 42 })

      assert_equal({ status: 404, id: nil }, scenario.answer.call(scenario.run.call))
    end
  end

  describe '.env' do
    it 'has no content headers without a body' do
      refute_includes requests.env('GET', '/todos/42', '').keys, 'CONTENT_TYPE'
    end

    it 'describes a JSON body' do
      env = requests.env('POST', '/todos', '{}')

      assert_equal %w[application/json 2], env.values_at('CONTENT_TYPE', 'CONTENT_LENGTH')
    end

    it 'is frozen, so no request can change it' do
      assert_predicate requests.env('GET', '/', ''), :frozen?
    end
  end

  describe '.call' do
    let(:echo) { ->(env) { [200, {}, [env.fetch('rack.input').read]] } }

    it 'gives each request a rack.input of its own' do
      env = requests.env('POST', '/', '{}')

      assert_equal [[200, '{}'], [200, '{}']], Array.new(2) { requests.call(echo, env, '{}') }
    end
  end

  describe '.read' do
    it "joins the body's chunks" do
      assert_equal 'ab', requests.read(%w[a b])
    end

    it 'closes a body that can be closed' do
      closable = Class.new do
        attr_reader :closed

        def each(&) = %w[a].each(&)

        def close
          @closed = true
        end
      end
      body = closable.new
      requests.read(body)

      assert body.closed
    end
  end
end
