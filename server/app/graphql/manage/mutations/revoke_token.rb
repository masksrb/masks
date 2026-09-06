module Manage
  module Mutations
    class RevokeToken < BaseMutation
      argument :id, ID
      argument :family, Boolean, required: false

      field :revoked, Integer, null: false
      field :token, Types::TokenType, null: false

      def resolve(id:, family: false)
        token = ::Token.where(type: Types::TokenType::GRANTS).find_by(id: id) ||
          refuse!("no token with that id")

        revoked = family ? token.revoke_family! : token.revoke!

        audit!(
          ::Event::TOKEN_REVOKED,
          actor: token.actor, client: token.client,
          kind: Types::TokenType::KINDS[token.type], family: family, revoked: revoked
        )

        { revoked: revoked, token: token }
      end
    end
  end
end
