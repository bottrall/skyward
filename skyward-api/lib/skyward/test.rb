# frozen_string_literal: true

module Skyward::Test
  extend self

  # @rbs (Skyward::API::_RackApp app) -> Client
  def client(app) = Client.new(app)
end
