# frozen_string_literal: true

module Masks::Types
  class EntryType < BaseObject
    field :id, String, null: true
    field :request_id, String, null: true
    field :prompt, String, null: true
    field :warnings, [String], null: false
    field :error, String, null: true
    field :redirect_uri, String, null: true
    field :scopes, [ScopeType], null: true
    field :actor, ActorType, null: true
    field :login_link, LoginLinkType, null: true
    field :client, ClientType, null: true
    field :extras, CamelizedJson, null: true
    field :settings, SettingsType, null: true

    bool :settled
    bool :trusted
  end
end
