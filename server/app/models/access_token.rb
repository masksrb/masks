class AccessToken < Token
  def self.lifetime
    1.hour
  end

  def self.issue!(issuer:, actor:, client:, scopes:, audience:, parent: nil, expires_at: nil, act: nil, requested_claims: nil)
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
      expires_at: ceiling
    )

    token.instance_variable_set(:@jwt, issuer.sign(token.claims(issuer, act: act)))
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
      "sub" => Subjects.for(actor, client),
      "aud" => audience.one? ? audience.first : audience,
      "exp" => expires_at.to_i,
      "iat" => created_at.to_i,
      "jti" => jti,
      "client_id" => client&.client_id,
      "scope" => Scopes.join(scopes),
      "act" => act,
      "tenant" => tenant.to_identity
    }.compact
  end
end
