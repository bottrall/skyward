# frozen_string_literal: true

module Skyward::ORM::Tables
  # @rbs!
  #   type on_delete = :cascade | :restrict | :set_null | :set_default | :no_action
  #   type refinement = :uuid | :int32 | :int16
  #   type column_type = Skyward::Core::Types::scalar | :enum | refinement | :json
end
