class Issuer
  ACR_PASSWORD = "urn:masks:acr:pwd".freeze
  ACR_MULTI_FACTOR = "urn:masks:acr:mfa".freeze
  MULTI_FACTOR = "mfa".freeze
  ACR_VALUES = [ ACR_PASSWORD, ACR_MULTI_FACTOR ].freeze
  LOGOUT_EVENT = "http://schemas.openid.net/event/backchannel-logout".freeze
  LOGOUT_TOKEN_LIFETIME = 2.minutes

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

  def manage_resource
    "#{url}/manage"
  end

  def connections_resource
    "#{url}/connections"
  end

  def connection_scopes
    Tenant.switch(tenant) { Provider.active.map(&:release_scope) }
  end

  def protected_resource
    {
      "resource" => manage_resource,
      "authorization_servers" => [ url ],
      "scopes_supported" => [ Scopes::MANAGE ],
      "bearer_methods_supported" => [ "header" ],
      "tenant" => tenant.to_identity
    }.merge(manage_descriptions)
  end

  def manage_descriptions
    default = { "scope_descriptions" => described_manage(I18n.default_locale) }

    Locales.available.reduce(default) do |held, locale|
      held.merge("scope_descriptions##{Locales.tag(locale)}" => described_manage(locale))
    end
  end

  def described_manage(locale)
    { Scopes::MANAGE => Scopes.description_for(Scopes::MANAGE, locale: locale) }
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

  def subject_for(actor, client)
    Subjects.for(actor, client)
  end

  def id_token(actor:, client:, nonce: nil, issued_at: Time.current,
               authenticated_at: nil, access_token: nil, code: nil, amr: nil, sid: nil)
    subject = subject_for(actor, client)

    sign({
      "iss" => url,
      "sub" => subject,
      "aud" => client.client_id,
      "exp" => 15.minutes.from_now.to_i,
      "iat" => issued_at.to_i,
      "auth_time" => (authenticated_at || issued_at).to_i,
      "acr" => acr_for(amr),
      "amr" => Array(amr).presence,
      "nonce" => nonce,
      "sid" => sid,
      "at_hash" => half_hash(access_token),
      "c_hash" => half_hash(code),
      "tenant" => tenant.to_identity,
      Actor::AVATARS_CLAIM => Avatars.urls(actor, origin: url, subject: subject)
    }.compact)
  end

  def logout_token(client:, subject:, sid: nil, issued_at: Time.current)
    sign({
      "iss" => url,
      "aud" => client.client_id,
      "iat" => issued_at.to_i,
      "exp" => (issued_at + LOGOUT_TOKEN_LIFETIME).to_i,
      "jti" => SecureRandom.uuid,
      "events" => { LOGOUT_EVENT => {} },
      "sub" => subject,
      "sid" => sid
    }.compact)
  end

  def acr_for(amr)
    Array(amr).include?(MULTI_FACTOR) ? ACR_MULTI_FACTOR : ACR_PASSWORD
  end

  def discovery
    {
      "issuer" => url,
      "tenant" => tenant.to_identity,
      "authorization_endpoint" => "#{url}/authorize",
      "token_endpoint" => "#{url}/token",
      "userinfo_endpoint" => "#{url}/userinfo",
      "avatar_endpoint" => "#{url}/avatars",
      "avatar_styles_supported" => Avatars::STYLES,
      "avatar_sizes_supported" => Avatars::SIZES,
      "jwks_uri" => "#{url}/.well-known/jwks.json",
      "registration_endpoint" => "#{url}/register",
      "pushed_authorization_request_endpoint" => "#{url}/par",
      "handshake_endpoint" => "#{url}/handshake",
      "masks_protocol_version" => Masks::PROTOCOL_VERSION,
      "revocation_endpoint" => "#{url}/revoke",
      "introspection_endpoint" => "#{url}/introspect",
      "end_session_endpoint" => "#{url}/logout",
      "frontchannel_logout_supported" => false,
      "backchannel_logout_supported" => true,
      "backchannel_logout_session_supported" => true,
      "scopes_supported" => Scopes::DESCRIBED.keys + connection_scopes,
      "ui_locales_supported" => Locales.available.map { |locale| Locales.tag(locale) },
      "response_types_supported" => Client::RESPONSE_TYPES,
      "response_modes_supported" => [ "query" ],
      "grant_types_supported" => Client::GRANT_TYPES,
      "revocation_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "introspection_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "subject_types_supported" => Subjects::TYPES,
      "acr_values_supported" => ACR_VALUES,
      "id_token_signing_alg_values_supported" => [ SigningKey::ALGORITHM ],
      "token_endpoint_auth_methods_supported" => Client::AUTH_METHODS,
      "code_challenge_methods_supported" => Client::CHALLENGE_METHODS,
      "claims_supported" => %w[
        iss sub aud exp iat auth_time nonce sid
        preferred_username name picture email email_verified tenant act
      ] + [ Actor::AVATARS_CLAIM ],
      "authorization_response_iss_parameter_supported" => true,
      "resource_indicators_supported" => true,
      "require_pushed_authorization_requests" => false,
      "request_parameter_supported" => false,
      "request_uri_parameter_supported" => false,
      "claims_parameter_supported" => true
    }
  end
end
