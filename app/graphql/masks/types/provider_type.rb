# frozen_string_literal: true

module Masks::Types
  class ProviderType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :id, ID, null: true

    Masks::Provider.settings.each do |key, conf|
      field key, conf[:graphql], null: true unless conf[:writer]
    end

    field :settings, CamelizedJson, null: true
    field :callback_uri, String, null: true
    field :disabled, Boolean, null: true
    field :setup, Boolean, null: true
    field :clients, ClientType.connection_type, null: true

    def id
      object.key
    end

    def type
      object.public_type
    end

    def setup
      object.setup?
    end

    def settings
      object
        .type_settings
        .map { |k, conf| [k, object.typed.setting(k)] unless conf[:writer] }
        .compact
        .to_h
    end
  end
end
