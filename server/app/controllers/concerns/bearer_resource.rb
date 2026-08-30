module BearerResource
  extend ActiveSupport::Concern

  private

    # Resource::Bearer is written as Rack middleware, which would run before the
    # tenant is resolved and verify tokens against the wrong issuer. Called from
    # inside the action it inherits the tenant, and lends us RFC 6750 token
    # extraction — header or payload, and the refusal when a caller sends both —
    # along with the WWW-Authenticate shapes for every way this can fail.
    def with_access_token(scope: nil)
      token = nil

      handler = Rack::OAuth2::Server::Resource::Bearer.new(
        ->(_env) { [ 200, {}, [] ] }, issuer.url
      ) { |bearer| token = verify!(bearer, scope: scope) }

      answer = handler.call(request.env)

      return render_rack(answer) unless answer.first == 200
      return refuse_token("a bearer token is required") if token.nil?

      yield token
    end

    def verify!(bearer, scope: nil)
      token = AccessToken.live.find_by(digest: decode(bearer)["jti"])

      bearer.invalid_token!("that token has been revoked") if token.nil?

      if scope.present? && !token.scope_list.include?(scope.to_s)
        bearer.insufficient_scope!("this token does not carry #{scope}", scope: scope)
      end

      token
    end

    def decode(bearer)
      JWT.decode(
        bearer.access_token, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: issuer.jwks,
        iss: issuer.url, verify_iss: true,
        verify_expiration: true,
        required_claims: %w[iss sub exp jti]
      ).first
    rescue JWT::DecodeError => e
      bearer.invalid_token!(e.message)
    end

    def refuse_token(description)
      render_rack(
        Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new(
          :invalid_token, description, realm: issuer.url
        ).finish
      )
    end
end
