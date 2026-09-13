module Manage
  module Types
    class ProviderPresetType < BaseObject
      field :key, ID, null: false
      field :name, String, null: false
      field :protocol, String, null: false
      field :asks, [ String ], null: false
      field :needs, [ String ], null: false
      field :defaults, GraphQL::Types::JSON, null: false
      field :guide, String
      field :trusts_email, Boolean, null: false
      field :custom, Boolean, null: false, method: :custom?
      field :delegated_scopes, [ String ], null: false
      field :delegates, Boolean, null: false, method: :delegates?
    end
  end
end
