module Manage
  module Mutations
    class RevokeProvisioningToken < BaseMutation
      argument :id, ID

      field :provisioning_token, Types::ProvisioningTokenType, null: false

      def resolve(id:)
        token = ::ProvisioningToken.live.find_by(id: id) || refuse!("no live provisioning token with that id")

        token.consume!
        audit!(::Event::PROVISIONING_TOKEN_REVOKED, label: token.label)

        { provisioning_token: token }
      end
    end
  end
end
