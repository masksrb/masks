class ClientAssertion
  class Refused < StandardError; end

  TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
  ALGORITHMS = ClientKeys::ALGORITHMS
  LEEWAY = 30
  LONGEST = 1.hour

  attr_reader :token

  def self.issuer_of(token)
    claims = JWT.decode(token.to_s, nil, false).first

    claims["sub"].presence || claims["iss"].presence
  rescue JWT::DecodeError
    nil
  end

  def initialize(token, client:, audiences:)
    @token = token.to_s
    @client = client
    @audiences = Array(audiences).map { |one| one.to_s.chomp("/") }
  end

  def verify!
    claims, = ClientKeys.new(client).decode(token, subject: "that client assertion")

    named!(claims)
    addressed!(claims)
    timely!(claims)
    once!(claims)

    self
  rescue ClientKeys::Refused => e
    raise Refused, e.message
  end

  private

    attr_reader :client, :audiences

    def named!(claims)
      unless claims["iss"] == client.client_id && claims["sub"] == client.client_id
        raise Refused, "a client assertion must name the client as both iss and sub"
      end
    end

    def addressed!(claims)
      named = Array(claims["aud"]).map { |one| one.to_s.chomp("/") }

      raise Refused, "that client assertion was made for another audience" if (named & audiences).empty?
    end

    def timely!(claims)
      expires = claims["exp"]
      now = Time.current.to_i

      raise Refused, "a client assertion must say when it expires" unless expires.is_a?(Numeric)
      raise Refused, "that client assertion has expired" if expires < now - LEEWAY
      raise Refused, "that client assertion lives longer than #{LONGEST.inspect}" if expires > now + LONGEST.to_i + LEEWAY

      raise Refused, "that client assertion was made in the future" if claims["iat"].is_a?(Numeric) && claims["iat"] > now + LEEWAY
      raise Refused, "that client assertion is not valid yet" if claims["nbf"].is_a?(Numeric) && claims["nbf"] > now + LEEWAY
    end

    def once!(claims)
      jti = claims["jti"].to_s

      raise Refused, "a client assertion must carry a jti" if jti.blank?

      key = "client-assertion:#{client.tenant_id}:#{client.id}:#{Digest::SHA256.hexdigest(jti)}"
      remaining = [ claims["exp"].to_i - Time.current.to_i + LEEWAY, LEEWAY ].max

      raise Refused, "that client assertion has already been used" unless Rails.cache.write(key, true, expires_in: remaining, unless_exist: true)
    end
end
