class Exchange
  GRANT_TYPE = "urn:ietf:params:oauth:grant-type:token-exchange".freeze
  ACCESS_TOKEN = PresentedToken::ACCESS_TOKEN
  ID_TOKEN = PresentedToken::ID_TOKEN
  UPSTREAM_ACCESS_TOKEN = "urn:masks:params:oauth:token-type:upstream_access_token".freeze
  TOKEN_TYPES = PresentedToken::TYPES
  REQUESTED_TOKEN_TYPES = [ ACCESS_TOKEN, UPSTREAM_ACCESS_TOKEN ].freeze

  attr_reader :client, :issuer, :subject_token, :subject_token_type, :actor_token, :actor_token_type,
              :requested_token_type, :requested_scopes, :requested_audience,
              :requested_lifetime, :named_audience

  def initialize(client:, issuer:, subject_token:, subject_token_type: nil, actor_token: nil, actor_token_type: nil,
                 requested_token_type: nil, scope: nil, resource: nil, lifetime: nil, audience: nil)
    @client = client
    @issuer = issuer
    @subject_token = subject_token
    @subject_token_type = subject_token_type.to_s
    @actor_token = actor_token.presence
    @actor_token_type = actor_token_type.to_s.presence
    @requested_token_type = (requested_token_type.presence || ACCESS_TOKEN).to_s
    @requested_scopes = Scopes.list(scope)
    @requested_audience = Array(resource).map(&:to_s).reject(&:empty?).uniq
    @requested_lifetime = lifetime.to_i if lifetime.present?
    @named_audience = Array(audience).map(&:to_s).reject(&:empty?).uniq
  end

  def upstream?
    requested_token_type == UPSTREAM_ACCESS_TOKEN
  end

  def subject
    return @subject if defined?(@subject)

    @subject = PresentedToken.read(subject_token, type: subject_token_type, issuer: issuer)
  end

  def acting
    return @acting if defined?(@acting)

    @acting = actor_token && PresentedToken.read(actor_token, type: actor_token_type, issuer: issuer)
  end

  def subject_access_token
    subject&.record
  end

  def actor
    subject&.actor
  end

  def connection
    return @connection if defined?(@connection)

    id = named_audience.one? ? named_audience.first : nil

    @connection = id&.match?(Subjects::UUID) ? Connection.includes(:provider).find_by(uuid: id) : nil
  end

  def delegation
    return @delegation if defined?(@delegation)

    @delegation = Delegation.covering(client: client, actor: actor, connection: connection)&.tap do |held|
      held.association(:connection).target = connection
    end
  end

  def release!
    upstream = delegation.release!

    {
      "access_token" => upstream["access_token"],
      "issued_token_type" => UPSTREAM_ACCESS_TOKEN,
      "token_type" => "Bearer",
      "expires_in" => [ (upstream["expires_at"] - Time.current).to_i, 0 ].max,
      "scope" => upstream["scope"].to_s
    }
  rescue Delegation::Refused => e
    Event.record!(Event::DELEGATION_REFUSED, actor: actor, by: nil, client: client,
                                             provider: connection.provider.key, connection: connection.uuid, reason: e.message)

    raise Policy::Denied.new("invalid_grant", e.message)
  rescue Delegation::Unavailable => e
    raise Policy::Denied.new("temporarily_unavailable", e.message, status: :service_unavailable)
  end

  def consent
    return @consent if defined?(@consent)

    @consent = actor && Consent.live.find_by(actor: actor, client: client)
  end

  def consented_scopes
    held = consent ? Scopes.union(consent.scopes, client.required_scopes) : client.required_scopes
    held = client.scope_list if client.approved? && !client.consent_required?

    actor ? Scopes.list(actor.permitted_scopes(held)) : []
  end

  def consented_audience
    Scopes.list((consent&.audience || []) + client.resources + [ client.client_id ])
  end

  def available_scopes
    subject.id_token? ? consented_scopes : subject.scope_list
  end

  def available_audience
    subject.id_token? ? consented_audience : subject.audience
  end

  def granted_scopes
    return available_scopes if requested_scopes.empty? && subject.access_token?
    return requested_scopes if requested_scopes.any?

    Scopes.list(available_scopes).reject { |scope| Scopes.prefix?(scope) }
  end

  def granted_audience
    return requested_audience if requested_audience.any?
    return subject.audience if subject.access_token?

    client.resources.presence || [ client.client_id ]
  end

  def expires_at
    ceiling = subject.expires_at
    return ceiling if requested_lifetime.nil?

    [ requested_lifetime.seconds.from_now, ceiling ].min
  end

  def actor_claim
    return nil if subject.id_token? && acting.nil?

    held = acting ? { "sub" => acting.subject, "client_id" => acting.client_id } : { "sub" => client.client_id }
    chain = subject.act

    held.merge("act" => chain).compact
  end

  def validate!
    ExchangePolicy.new(self).call
    self
  end

  def issue!(jkt: nil)
    AccessToken.issue!(
      issuer: issuer,
      actor: actor,
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
