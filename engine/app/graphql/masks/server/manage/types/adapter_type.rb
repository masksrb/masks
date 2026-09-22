module Masks
  module Server
    module Manage
      module Types
        class AdapterType < BaseObject
          field :key, ID, null: false
          field :name, String, null: false
          field :kind, String, null: false
          field :service, String, null: false
          field :label, String, null: false
          field :primary, Boolean, null: false
          field :settings, GraphQL::Types::JSON, null: false
          field :secrets_held, [ String ], null: false
          field :archived_at, GraphQL::Types::ISO8601DateTime
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

          def label
            object.class.label
          end

          def settings
            object.public_settings
          end
        end
      end
    end
  end
end
