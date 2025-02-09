# frozen_string_literal: true

module Masks::Types
  class ClientType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :id, ID
    field :type, String
    field :secret, String
    field :logo, String
    field :providers, [ProviderType]
    field :lifetime_types, [String], null: false
    field :scopes, GraphQL::Types::JSON, null: false
    field :consent, Boolean
    bool :internal

    field :stats, CamelizedJSON, null: false

    Masks::Client.settings.each do |key, conf|
      field key, conf[:graphql], null: true
    end

    def id
      object.key
    end

    def logo
      object.logo_url
    end

    def consent
      !object.auto_consent?
    end

    def lifetime_types
      Masks::Client::LIFETIME_SETTINGS.map { |c| c.to_s.camelize(:lower) }
    end

    def stats
      { tokens: object.tokens.count, actors: object.actors.count }
    end

    def allow_second_factor?
      object.second_factor?
    end
  end
end
