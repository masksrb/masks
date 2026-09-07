module CarriesAuthorization
  extend ActiveSupport::Concern

  class_methods do
    def attributes_for(authorization)
      {
        client: authorization.client,
        scopes: Scopes.join(authorization.requested_scopes),
        audience: authorization.audience,
        redirect_uri: authorization.redirect_uri,
        nonce: authorization.nonce,
        code_challenge: authorization.code_challenge,
        code_challenge_method: authorization.code_challenge_method,
        requested_claims: authorization.requested_claims,
        jkt: authorization.dpop_jkt,
        payload: {
          "response_type" => authorization.response_type,
          "state" => authorization.state,
          "prompt" => authorization.prompt,
          "max_age" => authorization.max_age,
          "user_code" => authorization.user_code
        }.compact
      }
    end
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
      claims: requested_claims,
      user_code: held("user_code"),
      dpop_jkt: jkt
    )
  end

  def device?
    authorization.device?
  end

  def held(key)
    (payload || {})[key]
  end
end
