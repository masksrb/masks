module Masks
  module Server
    module Manage
      module Types
        class DomainClaimType < BaseObject
          field :domain, ID, null: false
          field :record_name, String, null: false, description: "The DNS name to publish a TXT record at."
          field :record_value, String, null: false, description: "The TXT record's value."
          field :verified_at, GraphQL::Types::ISO8601DateTime
          field :checked_at, GraphQL::Types::ISO8601DateTime
          field :missing_since, GraphQL::Types::ISO8601DateTime, description: "When a proven record stopped answering. The claim is released a week later."
          field :provider, ProviderType, description: "The provider people with an address here are sent to."
        end
      end
    end
  end
end
