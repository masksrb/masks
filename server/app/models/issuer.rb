class Issuer
  attr_reader :tenant, :origin

  def initialize(tenant, origin)
    @tenant = tenant
    @origin = origin.to_s.chomp("/")
  end

  def url
    origin
  end

  def key
    @key ||= tenant.signing_key
  end

  def sign(claims)
    key.sign(claims)
  end

  def jwks
    { "keys" => Tenant.switch(tenant) { SigningKey.published.map(&:public_jwk) } }
  end

  def id_token(actor:, client:, scopes:, nonce: nil, issued_at: Time.current)
    sign({
      "iss" => url,
      "sub" => actor.uuid,
      "aud" => client.client_id,
      "exp" => 15.minutes.from_now.to_i,
      "iat" => issued_at.to_i,
      "auth_time" => issued_at.to_i,
      "nonce" => nonce,
      "tenant" => tenant.to_identity
    }.compact.merge(actor.claims(scopes)))
  end

  def discovery
    {
      "issuer" => url,
      "tenant" => tenant.to_identity,
      "authorization_endpoint" => "#{url}/authorize",
      "token_endpoint" => "#{url}/token",
      "userinfo_endpoint" => "#{url}/userinfo",
      "jwks_uri" => "#{url}/.well-known/jwks.json",
      "registration_endpoint" => "#{url}/register",
      "end_session_endpoint" => "#{url}/logout",
      "scopes_supported" => Scopes::DESCRIBED.keys,
      "response_types_supported" => Client::RESPONSE_TYPES,
      "response_modes_supported" => [ "query" ],
      "grant_types_supported" => Client::GRANT_TYPES,
      "subject_types_supported" => [ "public" ],
      "id_token_signing_alg_values_supported" => [ SigningKey::ALGORITHM ],
      "token_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "code_challenge_methods_supported" => Client::CHALLENGE_METHODS,
      "claims_supported" => %w[
        iss sub aud exp iat auth_time nonce
        preferred_username name email email_verified tenant
      ],
      "authorization_response_iss_parameter_supported" => true,
      "resource_indicators_supported" => true,
      "require_pushed_authorization_requests" => false
    }
  end
end
