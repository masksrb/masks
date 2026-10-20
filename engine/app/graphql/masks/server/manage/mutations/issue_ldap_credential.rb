module Masks
  module Server
    module Manage
      module Mutations
        class IssueLdapCredential < BaseMutation
          requires :owner

          description "Issues a bind DN and secret an app uses to search this tenant's LDAP directory. The secret is returned once."

          argument :label, String, description: "Lowercase letters, digits, dots, dashes, and underscores. It becomes the cn of the bind DN."
          argument :client_id, ID, required: false,
                   description: "The client this app is registered as. People who make an app password for that client can bind with it on a connection that bound with this credential first."

          field :ldap_credential, Types::LdapCredentialType, null: false
          field :secret, String, null: false

          def resolve(label:, client_id: nil)
            client = client_id.present? ? client!(client_id) : nil
            credential = Masks::Server::LdapCredential.issue!(label: label, by: viewer, client: client)

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
