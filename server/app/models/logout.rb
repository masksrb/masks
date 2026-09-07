class Logout
  class Refused < StandardError
    attr_reader :code

    def initialize(code, message)
      super(message)
      @code = code
    end
  end

  attr_reader :state, :redirect_uri

  def initialize(issuer:, id_token_hint: nil, client_id: nil, post_logout_redirect_uri: nil, state: nil)
    @issuer = issuer
    @hint = id_token_hint.presence
    @client_id = client_id.presence
    @redirect_uri = post_logout_redirect_uri.presence
    @state = state.presence

    verify!
  end

  def client
    @client ||= verified_client
  end

  def verified?
    claims.present?
  end

  def redirect_to
    return nil if redirect_uri.nil?

    pairs = state ? [ [ "state", state ] ] : []
    pairs.any? ? "#{redirect_uri}?#{URI.encode_www_form(pairs)}" : redirect_uri
  end

  def subject
    claims && claims["sub"]
  end

  def names?(actor)
    return false if actor.nil? || subject.blank?

    Subjects.locate(subject)&.id == actor.id
  end

  private

    def claims
      return @claims if defined?(@claims)

      @claims = @hint && decode(@hint)
    end

    def decode(token)
      JWT.decode(
        token, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: @issuer.jwks,
        iss: @issuer.url, verify_iss: true,
        verify_expiration: false,
        required_claims: %w[iss aud]
      ).first
    rescue JWT::DecodeError
      raise Refused.new("invalid_request", "the id_token_hint is not a token this issuer signed")
    end

    def verified_client
      named = claims ? Array(claims["aud"]).first : @client_id
      return nil if named.blank?

      Client.authenticating(named)
    end

    def verify!
      return if redirect_uri.nil?

      if client.nil?
        raise Refused.new(
          "invalid_request",
          "a post_logout_redirect_uri needs an id_token_hint or a client_id to be checked against"
        )
      end

      return if client.post_logout_redirect_uris.include?(redirect_uri)

      raise Refused.new(
        "invalid_request",
        "post_logout_redirect_uri is not registered for this client"
      )
    end
end
