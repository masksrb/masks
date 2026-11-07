module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Directory
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :provisioning_tokens, [ ProvisioningTokenType ], null: false
              field :scim_base_url, String, null: false
              field :ldap_credentials, [ LdapCredentialType ], null: false
              field :ldap_base_dn, String, null: false, description: "The base DN of this tenant's LDAP directory."
              field :ldap_port, Integer, null: false, description: "The port masks serves LDAP on."
              field :ldap_tls, Boolean, null: false, description: "Whether that port speaks LDAPS."
              field :ldap_local_only, Boolean, null: false,
                    description: "Whether the directory answers only on the server's own machine, " \
                                 "since it has no certificate and MASKS_LDAP_PLAINTEXT is not set."
            end

            def provisioning_tokens
              ProvisioningToken.live.order(created_at: :desc)
            end

            def scim_base_url
              Scim.base(Issuer.new(Current.tenant, Current.origin))
            end

            def ldap_credentials
              LdapCredential.live.order(created_at: :desc)
            end

            def ldap_base_dn
              Ldap::Directory.base_for(Current.tenant).to_s
            end

            def ldap_port
              ::Rails.configuration.masks.ldap_port
            end

            def ldap_tls
              ::Rails.configuration.masks.ldap_cert.present?
            end

            def ldap_local_only
              Ldap::Listener.local_only?
            end
          end
        end
      end
    end
  end
end
