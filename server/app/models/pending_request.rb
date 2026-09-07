class PendingRequest < Token
  include CarriesAuthorization

  def self.lifetime
    1.hour
  end

  def self.answered_is_final?
    true
  end

  def self.open!(authorization)
    mint!(**attributes_for(authorization))
  end

  def fingerprint
    authorization.fingerprint
  end

  def reauthenticate?
    authorization.reauthenticate?
  end

  def consent?
    authorization.consent?
  end

  def silent?
    authorization.silent?
  end

  def max_age
    held("max_age")
  end

  def scopes_for(actor)
    authorization.scopes_for(actor)
  end

  def issue_code!(actor:, device: nil, session: nil, authenticated_at: nil, amr: nil)
    AuthorizationCode.mint!(
      actor: actor,
      device: device,
      session: session,
      parent: self,
      authenticated_at: authenticated_at,
      payload: { "amr" => Array(amr) },
      client: client,
      scopes: Scopes.join(scopes_for(actor)),
      audience: audience,
      redirect_uri: redirect_uri,
      requested_claims: requested_claims,
      nonce: nonce,
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method
    )
  end

  def issued
    children.find_by(type: AuthorizationCode.name)
  end
end
