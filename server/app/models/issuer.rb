class Issuer
  ACR_PASSWORD = "urn:masks:acr:pwd".freeze
  ACR_MULTI_FACTOR = "urn:masks:acr:mfa".freeze
  ACR_VALUES = [ ACR_PASSWORD, ACR_MULTI_FACTOR ].freeze

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

  def half_hash(value)
    return nil if value.blank?

    digest = OpenSSL::Digest::SHA256.digest(value.to_s)

    Base64.urlsafe_encode64(digest[0, digest.bytesize / 2], padding: false)
  end

  def id_token(actor:, client:, nonce: nil, issued_at: Time.current,
               authenticated_at: nil, access_token: nil, code: nil)
    sign({
      "iss" => url,
      "sub" => actor.uuid,
      "aud" => client.client_id,
      "exp" => 15.minutes.from_now.to_i,
      "iat" => issued_at.to_i,
      "auth_time" => (authenticated_at || issued_at).to_i,
      "acr" => acr_for(actor),
      "nonce" => nonce,
      "at_hash" => half_hash(access_token),
      "c_hash" => half_hash(code),
      "tenant" => tenant.to_identity
    }.compact)
  end

  def acr_for(actor)
    actor.otp? ? ACR_MULTI_FACTOR : ACR_PASSWORD
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
      "handshake_endpoint" => "#{url}/handshake",
      "masks_protocol_version" => Masks::PROTOCOL_VERSION,
      "revocation_endpoint" => "#{url}/revoke",
      "introspection_endpoint" => "#{url}/introspect",
      "end_session_endpoint" => "#{url}/logout",
      "frontchannel_logout_supported" => false,
      "backchannel_logout_supported" => false,
      "scopes_supported" => Scopes::DESCRIBED.keys,
      "response_types_supported" => Client::RESPONSE_TYPES,
      "response_modes_supported" => [ "query" ],
      "grant_types_supported" => Client::GRANT_TYPES,
      "revocation_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "introspection_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "subject_types_supported" => [ "public" ],
      "acr_values_supported" => ACR_VALUES,
      "id_token_signing_alg_values_supported" => [ SigningKey::ALGORITHM ],
      "token_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "code_challenge_methods_supported" => Client::CHALLENGE_METHODS,
      "claims_supported" => %w[
        iss sub aud exp iat auth_time nonce
        preferred_username name email email_verified tenant act
      ],
      "authorization_response_iss_parameter_supported" => true,
      "resource_indicators_supported" => true,
      "require_pushed_authorization_requests" => false,
      "request_parameter_supported" => false,
      "request_uri_parameter_supported" => false,
      "claims_parameter_supported" => true
    }
  end
end
