module Masks
  module Server
    module Manage
      module Mutations
        class IssueLdapCredential < BaseMutation
          requires :owner

          description "Issues a bind DN and secret an app uses to search this tenant's LDAP directory. The secret is returned once."

          argument :label, String, description: "Lowercase letters, digits, dots, dashes, and underscores. It becomes the cn of the bind DN."

          field :ldap_credential, Types::LdapCredentialType, null: false
          field :secret, String, null: false

          def resolve(label:)
            credential = Masks::Server::LdapCredential.issue!(label: label, by: viewer)

            audit!(Masks::Server::Event::LDAP_CREDENTIAL_ISSUED, label: credential.label)

            { ldap_credential: credential, secret: credential.secret }
          rescue Masks::Server::LdapCredential::Refused => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
