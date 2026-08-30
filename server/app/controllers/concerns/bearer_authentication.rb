module BearerAuthentication
  extend ActiveSupport::Concern

  private

    def access_token
      @access_token ||= begin
        token = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
        challenge!("a bearer token is required") if token.nil?

        claims = decode(token)
        AccessToken.live.find_by(digest: claims["jti"]) ||
          challenge!("that token has been revoked")
      end
    end

    def decode(token)
      JWT.decode(
        token, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: issuer.jwks,
        iss: issuer.url, verify_iss: true,
        verify_expiration: true,
        required_claims: %w[iss sub exp jti]
      ).first
    rescue JWT::DecodeError => e
      challenge!(e.message)
    end

    def require_scope!(scope)
      return access_token if access_token.scope_list.include?(scope.to_s)

      raise Policy::Denied.new(
        "insufficient_scope", "this token does not carry #{scope}", status: :forbidden
      )
    end

    def challenge!(description)
      response.headers["WWW-Authenticate"] =
        %(Bearer error="invalid_token", error_description="#{description.tr('"', "'")}")

      raise Policy::Denied.new("invalid_token", description, status: :unauthorized)
    end
end
