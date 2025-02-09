# frozen_string_literal: true

module Masks::Types
  class InstallationType < BaseObject
    field :name, String, null: false
    field :url, String, null: false
    field :light_logo_url, String, null: true
    field :dark_logo_url, String, null: true
    field :favicon_url, String, null: true
    field :timezone, String, null: false
    field :region, String, null: false
    field :needs_restart, Boolean, null: true
    field :provider_types, [ProviderType], null: false
    field :theme, CamelizedJSON, null: false
    field :emails, CamelizedJSON, null: false
    field :nicknames, CamelizedJSON, null: false
    field :passwords, CamelizedJSON, null: false
    field :backup_codes, CamelizedJSON, null: false
    field :clients, CamelizedJSON, null: false
    field :sessions, CamelizedJSON, null: false
    field :devices, CamelizedJSON, null: false
    field :actors, CamelizedJSON, null: false
    field :stats, CamelizedJSON, null: false
    field :recent_clients, [ClientType], null: false
    field :recent_actors, [ActorType], null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    bool :writable

    def recent_actors
      Masks::Actor.limit(10).order(created_at: :desc)
    end

    def recent_clients
      Masks::Client.limit(10).order(created_at: :desc)
    end

    def favicon
      object.favicon_url
    end

    def stats
      {
        actors: Masks::Actor.count,
        emails: Masks::Email.count,
        phones: Masks::Phone.count,
        clients: Masks::Client.count,
        devices: Masks::Device.count,
        tokens: Masks::Token.count,
      }
    end
  end
end
