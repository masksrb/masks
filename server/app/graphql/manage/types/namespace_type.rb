module Manage
  module Types
    class NamespaceType < BaseObject
      field :name, String, null: false
      field :resource, String, null: false
      field :client, ClientType
      field :claimed_at, GraphQL::Types::ISO8601DateTime, null: false
      field :releasable, Boolean, null: false
      field :scopes, [ String ], null: false

      def releasable
        object.releasable?
      end

      def scopes
        ResourceMetadata.new(object.resource).descriptions.keys.select do |scope|
          scope.start_with?(object.name)
        end
      end
    end
  end
end
