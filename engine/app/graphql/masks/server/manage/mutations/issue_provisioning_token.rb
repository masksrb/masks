module Masks
  module Server
    module Manage
      module Mutations
        class IssueProvisioningToken < BaseMutation
          requires :security

          argument :label, String
          argument :expires_in, Integer, required: false
          argument :organization, ID, required: false,
                                      description: "An organization's key. The token then sees and adds only that organization's members."

          field :provisioning_token, Types::ProvisioningTokenType, null: false
          field :secret, String, null: false

          def resolve(label:, expires_in: nil, organization: nil)
            refuse!("a provisioning token lives for a positive number of seconds") if expires_in && !expires_in.positive?

            held = organization && (Masks::Server::Organization.active.find_by(key: organization) || refuse!("no organization keyed #{organization}"))
            token = Masks::Server::ProvisioningToken.issue!(label: label, by: viewer, expires_in: expires_in, organization: held)

            audit!(Masks::Server::Event::PROVISIONING_TOKEN_ISSUED, label: token.label, expires_at: token.expires_at.iso8601,
                                                                    organization: held&.key)

            { provisioning_token: token, secret: token.secret }
          end
        end
      end
    end
  end
end
