# frozen_string_literal: true

module Masks::Types
  module RelayNodeType
    include BaseInterface
    # Add the `id` field
    include GraphQL::Types::Relay::NodeBehaviors
  end
end
