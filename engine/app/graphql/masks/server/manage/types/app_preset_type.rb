module Masks
  module Server
    module Manage
      module Types
        class AppPresetType < BaseObject
          description "A self-hosted app masks knows how to register."

          field :key, ID, null: false
          field :name, String, null: false
          field :asks, GraphQL::Types::JSON, null: false,
                description: "Values the app's redirect URIs need beyond its address, with their usual defaults."
          field :scopes, [ String ], null: false
          field :guide, String
        end
      end
    end
  end
end
