module Masks
  module Server
    module Manage
      module Types
        class ReleaseType < BaseObject
          description "A newer release of masks than the one this server runs."

          field :version, String, null: false
          field :url, String, null: false, description: "The release notes."
          field :operator_step, Boolean, null: false, description: "Whether the release notes carry a line that starts with Operator:."
          field :checked_at, GraphQL::Types::ISO8601DateTime, null: false
        end
      end
    end
  end
end
