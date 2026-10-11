module Masks
  module Server
    module Manage
      module Mutations
        class RevokeLdapCredential < BaseMutation
          requires :owner

          description "Revokes an LDAP credential. Apps binding with it are refused from then on."

          argument :id, ID

          field :ldap_credential, Types::LdapCredentialType, null: false

          def resolve(id:)
            credential = Masks::Server::LdapCredential.live.find_by(id: id) || refuse!("no live LDAP credential with that id")

            credential.consume!
            audit!(Masks::Server::Event::LDAP_CREDENTIAL_REVOKED, label: credential.label)

            { ldap_credential: credential }
          end
        end
      end
    end
  end
end
