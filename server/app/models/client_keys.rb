class ClientKeys
  class Refused < StandardError; end

  LIFETIME = 5.minutes
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3
  SECRET = %w[d p q dp dq qi k].freeze
  ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512].freeze
  KINDS = %w[RSA EC].freeze
  LEEWAY = 30
  LONGEST = 1.hour

  class << self
    def check!(value)
      held = value.is_a?(String) ? JSON.parse(value) : value
      keys = held.is_a?(Hash) ? held["keys"] : nil

      raise Refused, "must be a JSON Web Key Set with a keys array" unless keys.is_a?(Array) && keys.any?

      keys.each do |key|
        raise Refused, "every key must be a JSON object" unless key.is_a?(Hash)
        raise Refused, "#{key['kty'].presence || 'that'} is not a kind of key a client signs with" unless KINDS.include?(key["kty"])
        raise Refused, "a client's keys must be public" if key.keys.any? { |field| SECRET.include?(field.to_s) }

        JWT::JWK.new(key).verify_key
      end

      held
    rescue JSON::ParserError
      raise Refused, "is not JSON"
    rescue JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError => e
      raise Refused, "holds a key that cannot be read: #{e.message}"
    end

    def fetch(uri)
      held = URI.parse(uri.to_s)

      raise Refused, "must be an https URL" unless held.is_a?(URI::HTTPS) || (Rails.env.local? && held.is_a?(URI::HTTP))

      check!(Outbound.fetch!(held, open: OPEN_TIMEOUT, read: READ_TIMEOUT))
    rescue URI::InvalidURIError
      raise Refused, "is not a URI"
    rescue Outbound::Refused => e
      raise Refused, e.message
    end
  end

  attr_reader :client

  def initialize(client)
    @client = client
  end

  def keys(fresh: false)
    return Array(client.jwks&.dig("keys")) if client.jwks.present?
    return [] if client.jwks_uri.blank?

    Rails.cache.delete(cache_key) if fresh

    Array(Rails.cache.fetch(cache_key, expires_in: LIFETIME) { self.class.fetch(client.jwks_uri) }["keys"])
  end

  def remote?
    client.jwks.blank? && client.jwks_uri.present?
  end

  def decode(token, subject: "that token")
    header = JWT.decode(token.to_s, nil, false).last
    algorithm = header["alg"].to_s

    raise Refused, "#{algorithm.presence || 'that'} is not an algorithm #{subject} may be signed with" unless ALGORITHMS.include?(algorithm)

    verified = attempt(token, header, algorithm, fresh: false)
    verified ||= attempt(token, header, algorithm, fresh: true) if remote? && unknown_kid?(header)

    verified || raise(Refused, "#{subject} was not signed by a key this client registered")
  rescue JWT::DecodeError
    raise Refused, "#{subject} is not a readable JWT"
  end

  def timely!(claims, subject:)
    now = Time.current.to_i
    expires = claims["exp"]

    raise Refused, "#{subject} must say when it expires" unless expires.is_a?(Numeric)
    raise Refused, "#{subject} has expired" if expires < now - LEEWAY
    raise Refused, "#{subject} lives longer than #{LONGEST.inspect}" if expires > now + LONGEST.to_i + LEEWAY
    raise Refused, "#{subject} was made in the future" if claims["iat"].is_a?(Numeric) && claims["iat"] > now + LEEWAY
    raise Refused, "#{subject} is not valid yet" if claims["nbf"].is_a?(Numeric) && claims["nbf"] > now + LEEWAY
  end

  def once!(claims, kind:, subject:)
    remaining = [ claims["exp"].to_i - Time.current.to_i + LEEWAY, LEEWAY ].max

    raise Refused, "#{subject} has already been used" unless Replay.first?(kind, claims["jti"], within: client.id, expires_in: remaining)
  end

  private

    def unknown_kid?(header)
      kid = header["kid"].presence

      kid.nil? || keys.none? { |jwk| jwk.is_a?(Hash) && jwk["kid"] == kid }
    end

    def attempt(token, header, algorithm, fresh:)
      candidates(header, fresh).each do |jwk|
        return [ *JWT.decode(token.to_s, JWT::JWK.new(jwk).verify_key, true, algorithms: [ algorithm ], verify_expiration: false) ]
      rescue JWT::VerificationError, JWT::IncorrectAlgorithm, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
        next
      end

      nil
    end

    def candidates(header, fresh)
      held = keys(fresh: fresh).select { |jwk| jwk.is_a?(Hash) && jwk["use"].to_s != "enc" }
      kid = header["kid"].presence

      kid ? held.select { |jwk| jwk["kid"] == kid } : held
    end

    def cache_key
      "client-jwks:#{client.tenant_id}:#{client.id}:#{Digest::SHA256.hexdigest(client.jwks_uri.to_s)}"
    end
end
