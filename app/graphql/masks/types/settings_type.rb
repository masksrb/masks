# frozen_string_literal: true

module Masks::Types
  class SettingsType < BaseObject
    field :name, String, null: true
    field :url, String, null: true
    field :needs_restart, Boolean, null: true
    field :light_logo_url, String, null: true
    field :dark_logo_url, String, null: true
    field :favicon_url, String, null: true
    field :timezone, String, null: true
    field :region, String, null: true
    field :theme, CamelizedJson, null: true
    field :nicknames, CamelizedJson, null: true
    field :passwords, CamelizedJson, null: true
    field :backup_codes, CamelizedJson, null: true
  end
end
