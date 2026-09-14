class AccessToken < Token
  TYPE = "at+jwt".freeze
  TYPES = [ TYPE, "application/#{TYPE}" ].freeze

  def self.lifetime
    1.hour
  end

  def self.decode(secret, issuer:, verify_expiration: true, required: %w[iss exp jti])
    claims, header = JWT.decode(
      secret, nil, true,
      algorithms: [ SigningKey::ALGORITHM ],
      jwks: issuer.jwks,
      iss: issuer.url, verify_iss: true,
      verify_expiration: verify_expiration,
      required_claims: required
    )

    raise JWT::DecodeError, "that token is not an access token" unless TYPES.include?(header["typ"].to_s.downcase)

    claims
  end

  def self.issue!(issuer:, actor:, client:, scopes:, audience:, parent: nil, expires_at: nil, act: nil, requested_claims: nil, jkt: nil)
    ceiling = [ expires_at, lifetime.from_now ].compact.min

    token = create!(
      actor: actor,
      client: client,
      device: parent&.device,
      session: parent&.session,
      parent: parent,
      scopes: Scopes.join(scopes),
      audience: Array(audience),
      requested_claims: requested_claims,
      digest: SecureRandom.uuid,
      jkt: jkt,
      expires_at: ceiling
    )

    token.instance_variable_set(:@jwt, issuer.sign(token.claims(issuer, act: act), typ: TYPE))
    token
  end

  def jti
    digest
  end

  def jwt
    @jwt
  end

  def claims(issuer, act: nil)
    {
      "iss" => issuer.url,
      "sub" => issuer.subject_for(actor, client),
      "aud" => audience.one? ? audience.first : audience,
      "exp" => expires_at.to_i,
      "iat" => created_at.to_i,
      "jti" => jti,
      "client_id" => client&.client_id,
      "scope" => Scopes.join(scopes),
      "act" => act,
      "cnf" => confirmation,
      "tenant" => tenant.to_identity
    }.compact
  end

  def token_type
    bound? ? Proof::SCHEME : "Bearer"
  end
end
