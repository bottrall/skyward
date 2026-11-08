# frozen_string_literal: true

# rbs-inline only types a Data.define assigned to a bare constant name, so
# Route is assigned inside the module rather than as Skyward::API::Endpoints::Route.
module Skyward::API::Endpoints
  Route = Data.define(
    :verb, #: Symbol
    :path, #: String
    :to, #: Symbol
    :summary, #: String?
    :description #: String?
  )
end
