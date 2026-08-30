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

  # OIDC Core 3.1.3.6: the left half of the hash of the value, under the
  # algorithm the token is signed with, base64url encoded.
  def half_hash(value)
    return nil if value.blank?

    digest = OpenSSL::Digest::SHA256.digest(value.to_s)

    Base64.urlsafe_encode64(digest[0, digest.bytesize / 2], padding: false)
  end

  def id_token(actor:, client:, scopes:, nonce: nil, issued_at: Time.current,
               authenticated_at: nil, access_token: nil, code: nil)
    sign({
      "iss" => url,
      "sub" => actor.uuid,
      "aud" => client.client_id,
      "exp" => 15.minutes.from_now.to_i,
      "iat" => issued_at.to_i,
      "auth_time" => (authenticated_at || issued_at).to_i,
      "nonce" => nonce,
      "at_hash" => half_hash(access_token),
      "c_hash" => half_hash(code),
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
      "revocation_endpoint" => "#{url}/revoke",
      "end_session_endpoint" => "#{url}/logout",
      "scopes_supported" => Scopes::DESCRIBED.keys,
      "response_types_supported" => Client::RESPONSE_TYPES,
      "response_modes_supported" => [ "query" ],
      "grant_types_supported" => Client::GRANT_TYPES,
      "revocation_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "subject_types_supported" => [ "public" ],
      "id_token_signing_alg_values_supported" => [ SigningKey::ALGORITHM ],
      "token_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "code_challenge_methods_supported" => Client::CHALLENGE_METHODS,
      "claims_supported" => %w[
        iss sub aud exp iat auth_time nonce
        preferred_username name email email_verified tenant act
      ],
      "authorization_response_iss_parameter_supported" => true,
      "resource_indicators_supported" => true,
      "require_pushed_authorization_requests" => false
    }
  end
end
