# frozen_string_literal: true

module Skyward::Test
  extend self

  # @rbs (_App app) -> Client
  def client(app) = Client.new(app)
end
