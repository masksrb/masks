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

    mint!(
      **held,
      payload: held[:payload].merge("user_code" => code),
      user_code_digest: UserCodes.digest(code)
    )
  end

  def self.awaiting(value)
    code = UserCodes.read(value)

    return nil if code.nil?

    live.find_by(user_code_digest: UserCodes.digest(code))
  end

  def user_code
    held("user_code")
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

  def refuse!(by: nil)
    update!(payload: payload.merge("denied" => true))

    Event.record!(Event::DEVICE_CODE_REFUSED, actor: by, client: client)
  end

  def hurried?
    !Rails.cache.write("device:#{id}:polled", true, expires_in: INTERVAL, unless_exist: true)
  end

  def issue!(issuer:, jkt: nil)
    AccessToken.issue!(
      issuer: issuer,
      actor: actor,
      client: client,
      scopes: scopes_for(actor),
      audience: audience.presence || [ client.client_id ],
      parent: self,
      requested_claims: requested_claims,
      jkt: jkt
    )
  end
end
