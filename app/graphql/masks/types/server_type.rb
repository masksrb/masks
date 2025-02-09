# frozen_string_literal: true

module Masks::Types
  class ServerType < BaseObject
    Masks::Modes::Server
      .settings_json
      .except("provider_types")
      .each { |k, v| field k, v[:graphql], null: true }

    field :adapters, [AdapterType], null: false
    field :adapter_types, [AdapterType], null: false
    field :provider_types, [ProviderType], null: false
    field :default_client, ClientType, null: false
    field :stats, CamelizedJson, null: false

    def default_client
      Masks::Client.new
    end

    def adapters
      object.adapters.values
    end

    def provider_types
      object.provider_map.map do |type, cls|
        Masks::Provider.seed(key: nil, type: type)
      end
    end
  end
end
