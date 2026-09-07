module ResourceToken
  extend ActiveSupport::Concern

  class Refused < StandardError; end

  private

    def with_access_token(scope: nil, &block)
      return with_bound_token(scope: scope, &block) if dpop_presented?

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

      if token.bound?
        bearer.invalid_token!("that token is bound to a key, and needs the proof that holds it")
      end

      if scope.present? && !token.scope_list.include?(scope.to_s)
        bearer.insufficient_scope!("this token does not carry #{scope}", scope: scope)
      end

      token
    end

    def decode(bearer)
      claims_in_token(bearer.access_token)
    rescue JWT::DecodeError => e
      bearer.invalid_token!(e.message)
    end

    def claims_in_token(secret)
      JWT.decode(
        secret, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: issuer.jwks,
        iss: issuer.url, verify_iss: true,
        verify_expiration: true,
        required_claims: %w[iss sub exp jti]
      ).first
    end

    def credentials
      @credentials ||= request.authorization.to_s.split(" ", 2)
    end

    def dpop_presented?
      credentials.first.to_s.casecmp?(Proof::SCHEME)
    end

    def with_bound_token(scope: nil)
      token = bound_token!(credentials[1].to_s)

      if scope.present? && !token.scope_list.include?(scope.to_s)
        return refuse_proof("this token does not carry #{scope}", error: "insufficient_scope", scope: scope)
      end

      yield token
    rescue Proof::Refused => refusal
      refuse_proof(refusal.message, error: "invalid_dpop_proof")
    rescue Refused => refusal
      refuse_proof(refusal.message)
    end

    def bound_token!(secret)
      raise Refused, "a token is required" if secret.blank?

      token = held_token(secret)

      raise Refused, "that token has been revoked" if token.nil?
      raise Refused, "that token is not bound to a key" unless token.bound?

      unless token.bound_to?(proof_for(secret))
        raise Refused, "that proof was made with another key"
      end

      token
    end

    def proof_for(secret = nil)
      Proof.read!(request, url: "#{issuer.url}#{request.path}", access_token: secret)
    end

    def held_token(secret)
      AccessToken.live.find_by(digest: claims_in_token(secret)["jti"])
    rescue JWT::DecodeError
      nil
    end

    def presented_access_token
      secret = credentials[1].to_s

      return nil if secret.blank?
      return bound_token!(secret) if dpop_presented?

      token = held_token(secret)

      token unless token.nil? || token.bound?
    rescue Proof::Refused, Refused
      nil
    end

    def refuse_token(description)
      render_rack(
        Rack::OAuth2::Server::Resource::Bearer::Unauthorized.new(
          :invalid_token, description, realm: issuer.url
        ).finish
      )
    end

    def refuse_proof(description, error: "invalid_token", scope: nil)
      held = [
        %(realm="#{issuer.url}"),
        %(error="#{error}"),
        %(error_description="#{description.to_s.delete('"')}")
      ]

      held << %(scope="#{scope}") if scope.present?
      held << %(algs="#{Proof::ALGORITHMS.join(' ')}")

      response.headers["WWW-Authenticate"] = "#{Proof::SCHEME} #{held.join(', ')}"

      head(error == "insufficient_scope" ? :forbidden : :unauthorized)
    end
end
