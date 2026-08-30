class AccessToken < Token
  def self.lifetime
    1.hour
  end

  def self.issue!(issuer:, actor:, client:, scopes:, audience:)
    token = create!(
      actor: actor,
      client: client,
      scopes: Scopes.join(scopes),
      audience: Array(audience),
      digest: SecureRandom.uuid,
      expires_at: lifetime.from_now
    )

    token.instance_variable_set(:@jwt, issuer.sign(token.claims(issuer)))
    token
  end

  def jti
    digest
  end

  def jwt
    @jwt
  end

  def claims(issuer)
    {
      "iss" => issuer.url,
      "sub" => actor&.uuid,
      "aud" => audience.one? ? audience.first : audience,
      "exp" => expires_at.to_i,
      "iat" => created_at.to_i,
      "jti" => jti,
      "client_id" => client&.client_id,
      "scope" => Scopes.join(scopes),
      "tenant" => tenant.to_identity
    }.compact
  end
end
