# frozen_string_literal: true

module Masks::Types
  class InstallationType < BaseObject
    # field :name, String, null: false
    # field :url, String, null: false
    # field :light_logo_url, String, null: true
    # field :dark_logo_url, String, null: true
    # field :favicon_url, String, null: true
    # field :tz, String, null: false
    # field :region, String, null: false
    # field :needs_restart, Boolean, null: true
    # field :provider_types, [ProviderType], null: false
    # field :theme, CamelizedJson, null: false
    # field :emails, CamelizedJson, null: false
    # field :nicknames, CamelizedJson, null: false
    # field :passwords, CamelizedJson, null: false
    # field :backup_codes, CamelizedJson, null: false
    # field :clients, CamelizedJson, null: false
    # field :sessions, CamelizedJson, null: false
    # field :devices, CamelizedJson, null: false
    # field :actors, CamelizedJson, null: false
    # field :stats, CamelizedJson, null: false
    #
    Masks.conf.class.settings_json.each do |k, v|
      field k, v[:graphql], null: true
    end

    field :recent_clients, [ClientType], null: false
    field :recent_actors, [ActorType], null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # bool :writable

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
