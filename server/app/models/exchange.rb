class Exchange
  GRANT_TYPE = "urn:ietf:params:oauth:grant-type:token-exchange".freeze
  ACCESS_TOKEN = "urn:ietf:params:oauth:token-type:access_token".freeze
  TOKEN_TYPES = [ ACCESS_TOKEN ].freeze

  attr_reader :client, :issuer, :subject_token, :subject_token_type,
              :requested_token_type, :requested_scopes, :requested_audience,
              :requested_lifetime

  def initialize(client:, issuer:, subject_token:, subject_token_type: nil,
                 requested_token_type: nil, scope: nil, resource: nil, lifetime: nil)
    @client = client
    @issuer = issuer
    @subject_token = subject_token
    @subject_token_type = (subject_token_type.presence || ACCESS_TOKEN).to_s
    @requested_token_type = (requested_token_type.presence || ACCESS_TOKEN).to_s
    @requested_scopes = Scopes.list(scope)
    @requested_audience = Array(resource).map(&:to_s).reject(&:empty?).uniq
    @requested_lifetime = lifetime.to_i if lifetime.present?
  end

  def subject_access_token
    return @subject_access_token if defined?(@subject_access_token)

    @subject_access_token = AccessToken.live.find_by(digest: claims["jti"]) if claims
  end

  def claims
    return @claims if defined?(@claims)

    @claims = JWT.decode(
      subject_token, nil, true,
      algorithms: [ SigningKey::ALGORITHM ],
      jwks: issuer.jwks,
      iss: issuer.url, verify_iss: true,
      verify_expiration: true,
      required_claims: %w[iss exp jti]
    ).first
  rescue JWT::DecodeError
    @claims = nil
  end

  def granted_scopes
    return subject_access_token.scope_list if requested_scopes.empty?

    requested_scopes
  end

  def granted_audience
    return subject_access_token.audience if requested_audience.empty?

    requested_audience
  end

  def expires_at
    ceiling = subject_access_token.expires_at
    return ceiling if requested_lifetime.nil?

    [ requested_lifetime.seconds.from_now, ceiling ].min
  end

  def actor_claim
    chain = claims["act"]
    { "sub" => client.client_id }.tap { |act| act["act"] = chain if chain }
  end

  def validate!
    ExchangePolicy.new(self).call
    self
  end

  def issue!(jkt: nil)
    AccessToken.issue!(
      issuer: issuer,
      actor: subject_access_token.actor,
      client: client,
      scopes: granted_scopes,
      audience: granted_audience,
      parent: subject_access_token,
      expires_at: expires_at,
      act: actor_claim,
      jkt: jkt
    )
  end
end
