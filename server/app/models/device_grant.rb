class DeviceGrant < Token
  include CarriesAuthorization

  GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code".freeze
  INTERVAL = 5
  ATTEMPTS = 10

  def self.lifetime
    15.minutes
  end

  def self.open!(authorization)
    code = UserCodes.generate
    held = attributes_for(authorization)

    grant = mint!(
      **held,
      payload: held[:payload].merge("user_code" => code),
      user_code_digest: UserCodes.digest(code)
    )

    grant.instance_variable_set(:@user_code, code)
    grant
  end

  def self.awaiting(value)
    code = UserCodes.read(value)

    return nil if code.nil?

    live.find_by(user_code_digest: UserCodes.digest(code))
  end

  def self.for_pending(pending)
    awaiting(pending.authorization.user_code)
  end

  def user_code
    @user_code || held("user_code")
  end

  def device_code
    secret
  end

  def interval
    INTERVAL
  end

  def approved?
    actor_id.present?
  end

  def denied?
    held("denied").present?
  end

  def answered?
    approved? || denied?
  end

  def approve!(actor:, session: nil, device: nil, authenticated_at: nil, amr: nil)
    update!(
      actor: actor,
      session: session,
      device: device,
      authenticated_at: authenticated_at,
      payload: payload.merge("amr" => Array(amr))
    )
  end

  def deny!
    update!(payload: payload.merge("denied" => true))
  end

  def hurried?
    last = held("polled_at")

    last.present? && Time.iso8601(last) > INTERVAL.seconds.ago
  rescue ArgumentError
    false
  end

  def polled!
    update!(payload: payload.merge("polled_at" => Time.current.iso8601(6)))
  end

  def issue!(issuer:)
    AccessToken.issue!(
      issuer: issuer,
      actor: actor,
      client: client,
      scopes: scopes_for(actor),
      audience: audience.presence || [ client.client_id ],
      parent: self,
      requested_claims: requested_claims
    )
  end

  def scopes_for(actor)
    authorization.scopes_for(actor)
  end
end
