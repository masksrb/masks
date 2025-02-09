# frozen_string_literal: true

module Masks::Types
  class AuthType < BaseObject
    field :id, ID
    field :actor, ActorType, null: true
    field :device, DeviceType, null: false
  end
end
