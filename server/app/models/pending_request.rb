class PendingRequest < Token
  def self.lifetime
    1.hour
  end

  def self.answered_is_final?
    true
  end

  def self.open!(authorization)
    mint!(
      client: authorization.client,
      scopes: Scopes.join(authorization.requested_scopes),
      audience: authorization.audience,
      redirect_uri: authorization.redirect_uri,
      nonce: authorization.nonce,
      code_challenge: authorization.code_challenge,
      code_challenge_method: authorization.code_challenge_method,
      requested_claims: authorization.requested_claims,
      payload: {
        "response_type" => authorization.response_type,
        "state" => authorization.state,
        "prompt" => authorization.prompt,
        "max_age" => authorization.max_age
      }.compact
    )
  end

  def authorization
    @authorization ||= Authorization.new(
      client_id: client&.client_id,
      redirect_uri: redirect_uri,
      response_type: held("response_type"),
      scope: scopes,
      state: held("state"),
      nonce: nonce,
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method,
      prompt: Scopes.join(Array(held("prompt"))),
      max_age: held("max_age"),
      resource: audience,
      claims: requested_claims
    )
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

  def issue_code!(actor:, device: nil, authenticated_at: nil, amr: nil)
    AuthorizationCode.mint!(
      actor: actor,
      device: device,
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

  private

    def held(key)
      (payload || {})[key]
    end
end
