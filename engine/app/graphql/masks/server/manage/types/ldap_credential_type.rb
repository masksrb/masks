module Masks
  module Server
    module Manage
      module Types
        class LdapCredentialType < BaseObject
          field :id, ID, null: false
          field :label, String, null: false
          field :bind_dn, String, null: false, description: "The DN an app binds as, under ou=services in this tenant's directory."
          field :issued_by, ActorType
          field :used_at, GraphQL::Types::ISO8601DateTime, description: "When an app last bound with it, to within five minutes."
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false

          def bind_dn
            Ldap::Directory.new(Current.tenant).service_dn(object.label).to_s
          end
        end
      end
    end
  end
end
