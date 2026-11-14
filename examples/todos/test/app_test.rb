# frozen_string_literal: true

require 'test_helper'

describe 'App' do
  let(:client) { Skyward::API::Test.client(App) }

  describe 'GET /up' do
    it 'says the app is up' do
      assert_equal({ status: 'ok' }, client.get('/up').json)
    end
  end

  describe 'GET /todos' do
    it 'mounts the todos API' do
      assert_equal [], client.get('/todos').json
    end
  end

  describe 'GET /openapi.json' do
    it 'documents every endpoint' do
      paths = client.get('/openapi.json').json[:paths].keys

      assert_equal %i[/up /todos /todos/{id} /todos/{id}/complete], paths
    end
  end

  describe 'GET /docs' do
    it 'serves the API reference' do
      assert_includes client.get('/docs').body, '<title>Todos</title>'
    end
  end
end
