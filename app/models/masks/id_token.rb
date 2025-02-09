# frozen_string_literal: true

module Masks
  class IdToken < Token
    cleanup :expires_at do
      0.seconds
    end

    def bearer_token?
      true
    end

    def to_response_object(with = {})
      claims = {
        sub: client.subject(actor),
        iss: client.issuer,
        aud: client.audience,
        exp: expires_at.to_i,
        iat: created_at.to_i,
        nonce:,
      }

      id_token = OpenIDConnect::ResponseObject::IdToken.new(claims)
      id_token.code = with[:code] if with[:code]
      id_token.access_token = with[:access_token] if with[:access_token]
      id_token
    end

    def to_jwt(with = {})
      to_response_object(with).to_jwt(client.private_key) do |jwt|
        jwt.kid = client.kid
      end
    end
  end
end
