class ClientAssertion
  class Refused < StandardError; end

  TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
  ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512].freeze
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
    header = JWT.decode(token, nil, false).last
    algorithm = header["alg"].to_s

    raise Refused, "#{algorithm.presence || 'that'} is not an algorithm a client assertion may use" unless ALGORITHMS.include?(algorithm)

    claims = signed(header, algorithm)

    named!(claims)
    addressed!(claims)
    timely!(claims)
    once!(claims)

    self
  rescue JWT::DecodeError
    raise Refused, "that client assertion is not a readable JWT"
  end

  private

    attr_reader :client, :audiences

    def signed(header, algorithm)
      verified = attempt(header, algorithm, fresh: false)
      verified ||= attempt(header, algorithm, fresh: true) if keys.remote?

      verified || raise(Refused, "that client assertion was not signed by a key this client registered")
    end

    def attempt(header, algorithm, fresh:)
      candidates(header, fresh).each do |jwk|
        return JWT.decode(token, JWT::JWK.new(jwk).verify_key, true, algorithms: [ algorithm ], verify_expiration: false).first
      rescue JWT::VerificationError, JWT::IncorrectAlgorithm, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
        next
      end

      nil
    rescue ClientKeys::Refused => e
      raise Refused, "this client's keys could not be read: #{e.message}"
    end

    def candidates(header, fresh)
      held = keys.keys(fresh: fresh).select { |jwk| jwk.is_a?(Hash) && jwk["use"].to_s != "enc" }
      kid = header["kid"].presence

      kid ? held.select { |jwk| jwk["kid"] == kid } : held
    end

    def keys
      @keys ||= ClientKeys.new(client)
    end

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
