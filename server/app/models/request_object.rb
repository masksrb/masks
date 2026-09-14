class RequestObject
  class Refused < StandardError; end

  TYPE = "oauth-authz-req+jwt".freeze
  TYPES = [ TYPE, "application/#{TYPE}", "jwt", nil ].freeze
  LEEWAY = 30
  LONGEST = 1.hour
  CARRIED = %w[
    response_type redirect_uri scope state nonce code_challenge code_challenge_method
    prompt max_age resource claims dpop_jkt
  ].freeze

  def self.unpack!(authorization, issuer:)
    new(authorization.request_object, client: authorization.client, client_id: authorization.client_id, issuer: issuer).authorization
  end

  def initialize(token, client:, client_id:, issuer:)
    @token = token.to_s
    @client = client
    @client_id = client_id.to_s
    @issuer = issuer
  end

  def authorization
    claims = verified

    Authorization.new(
      client_id: client_id,
      redirect_uri: claims["redirect_uri"],
      response_type: claims["response_type"],
      scope: claims["scope"],
      state: claims["state"],
      nonce: claims["nonce"],
      code_challenge: claims["code_challenge"],
      code_challenge_method: claims["code_challenge_method"],
      prompt: claims["prompt"],
      max_age: claims["max_age"],
      resource: claims["resource"],
      claims: claims["claims"],
      dpop_jkt: claims["dpop_jkt"],
      signed: true
    )
  end

  private

    attr_reader :token, :client, :client_id, :issuer

    def verified
      raise Refused, "client_id is required beside a request object" if client_id.blank?
      raise Refused, "no client is registered with that client_id" if client.nil?
      raise Refused, "this client has registered no keys to sign a request object with" unless keys.any?

      claims, header = keys.decode(token, subject: "that request object")

      typed!(header)
      named!(claims)
      timely!(claims)
      contained!(claims)
      once!(claims)

      claims
    rescue ClientKeys::Refused => e
      raise Refused, e.message
    end

    def keys
      @keys ||= ClientKeys.new(client)
    end

    def typed!(header)
      held = header["typ"]&.to_s&.downcase

      raise Refused, "a request object is typed #{TYPE}, not #{header['typ']}" unless TYPES.include?(held)
    end

    def named!(claims)
      raise Refused, "a request object's iss must be the client that signed it" unless claims["iss"] == client.client_id
      raise Refused, "the client_id inside a request object must match the one beside it" unless claims["client_id"] == client_id

      unless Array(claims["aud"]).map { |one| one.to_s.chomp("/") }.include?(issuer.url)
        raise Refused, "a request object must be addressed to #{issuer.url}"
      end
    end

    def timely!(claims)
      now = Time.current.to_i
      expires = claims["exp"]

      raise Refused, "a request object must say when it expires" unless expires.is_a?(Numeric)
      raise Refused, "that request object has expired" if expires < now - LEEWAY
      raise Refused, "that request object lives longer than #{LONGEST.inspect}" if expires > now + LONGEST.to_i + LEEWAY
      raise Refused, "that request object is not valid yet" if claims["nbf"].is_a?(Numeric) && claims["nbf"] > now + LEEWAY
      raise Refused, "that request object was made more than #{LONGEST.inspect} ago" if claims["nbf"].is_a?(Numeric) && claims["nbf"] < now - LONGEST.to_i
    end

    def contained!(claims)
      raise Refused, "a request object may not carry another request" if claims.key?("request") || claims.key?("request_uri")
    end

    def once!(claims)
      jti = claims["jti"].to_s

      return if jti.blank?

      key = "request-object:#{client.tenant_id}:#{client.id}:#{Digest::SHA256.hexdigest(jti)}"
      remaining = [ claims["exp"].to_i - Time.current.to_i + LEEWAY, LEEWAY ].max

      raise Refused, "that request object has already been used" unless Rails.cache.write(key, true, expires_in: remaining, unless_exist: true)
    end
end
