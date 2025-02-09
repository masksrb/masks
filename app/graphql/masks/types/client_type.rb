# frozen_string_literal: true

module Masks::Types
  class ClientType < BaseObject
    implements GraphQL::Types::Relay::Node

    field :id, ID
    field :logo, String
    field :providers, [ProviderType]
    field :lifetime_types, [String], null: false
    field :consent, Boolean

    Masks::Client.settings.each do |key, conf|
      field key, conf[:graphql], null: true unless conf[:writer]
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
      Masks::Client.duration_settings.map { |c| c.to_s.camelize(:lower) }
    end

    def allow_second_factor?
      object.second_factor?
    end

    def redirect_uris
      object.redirect_uris_a
    end
  end
end
