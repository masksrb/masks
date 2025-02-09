# frozen_string_literal: true

module Masks::Types
  class SearchType < BaseObject
    field :actors, [ActorType], null: true
    field :clients, [ClientType], null: true
    field :devices, [DeviceType], null: true
    field :providers, [ProviderType], null: true
    field :tokens, [TokenType], null: true
    field :query, String, null: false
  end
end
