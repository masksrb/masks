module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Organizations
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :organizations, [ OrganizationType ], null: false do
                argument :archived, Boolean, required: false
                argument :limit, Integer, required: false, description: "At most this many, by name."
              end

              field :organization, OrganizationType do
                argument :key, ID
              end

              field :groups, [ GroupType ], null: false

              field :group, GroupType do
                argument :key, String
              end
            end

            def organizations(archived: false, limit: nil)
              Masks::Server::Organization.listed(archived).order(:name).limit(limit&.clamp(1, 100))
            end

            def organization(key:)
              Masks::Server::Organization.find_by(key: key)
            end

            def groups
              Masks::Server::Group.order(:name)
            end

            def group(key:)
              Masks::Server::Group.find_by(key: key)
            end
          end
        end
      end
    end
  end
end
