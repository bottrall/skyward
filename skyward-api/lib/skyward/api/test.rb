# frozen_string_literal: true

module Skyward::API::Test
  extend self

  # @rbs (Skyward::API::_RackApp app) -> Client
  def client(app) = Client.new(app)
end
