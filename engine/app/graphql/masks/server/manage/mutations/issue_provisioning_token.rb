module Masks
  module Server
    module Manage
      module Mutations
        class IssueProvisioningToken < BaseMutation
          argument :label, String
          argument :expires_in, Integer, required: false

          field :provisioning_token, Types::ProvisioningTokenType, null: false
          field :secret, String, null: false

          def resolve(label:, expires_in: nil)
            refuse!("a provisioning token lives for a positive number of seconds") if expires_in && !expires_in.positive?

            token = Masks::Server::ProvisioningToken.issue!(label: label, by: viewer, expires_in: expires_in)

            audit!(Masks::Server::Event::PROVISIONING_TOKEN_ISSUED, label: token.label, expires_at: token.expires_at.iso8601)

            { provisioning_token: token, secret: token.secret }
          end
        end
      end
    end
  end
end
