module Masks
  module Server
    module Manage
      module Types
        class EventStreamType < BaseObject
          field :key, ID, null: false
          field :name, String, null: false
          field :url, String, null: false
          field :actions, [ String ], null: false
          field :organization, "Masks::Server::Manage::Types::OrganizationType",
                description: "When set, only this organization's events are sent."
          field :last_delivered_at, GraphQL::Types::ISO8601DateTime
          field :last_failure, String
          field :archived_at, GraphQL::Types::ISO8601DateTime
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false
          field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
