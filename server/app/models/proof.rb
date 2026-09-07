class Proof
  class Refused < StandardError; end

  SCHEME = "DPoP".freeze
  HEADER = "HTTP_DPOP".freeze
  TYPE = "dpop+jwt".freeze

  ALGORITHMS = %w[ES256 ES384 ES512 PS256 PS384 PS512 RS256].freeze
  SECRET = %w[d p q dp dq qi k].freeze
  THUMBED = {
    "EC" => %w[crv kty x y],
    "RSA" => %w[e kty n]
  }.freeze

  LEEWAY = 30
  WINDOW = 60
  MEMORY = WINDOW + (LEEWAY * 2)

  attr_reader :jkt

  class << self
    def presented?(request)
      request.get_header(HEADER).present?
    end

    def read!(request, url:, access_token: nil)
      new(header(request), method: request.request_method, url: url)
        .check!(access_token: access_token)
    end

    def header(request)
      held = Array(request.get_header(HEADER).to_s.split(",")).map(&:strip).reject(&:empty?)

      raise Refused, "exactly one DPoP proof is required" unless held.one?

      held.first
    end

    def thumbprint(jwk)
      named = THUMBED[jwk["kty"]]

      raise Refused, "the proof key is of a kind this server does not read" if named.nil?

      held = named.index_with { |field| jwk[field] }

      raise Refused, "the proof key is missing part of itself" if held.any? { |_, value| value.blank? }

      Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(JSON.generate(held)), padding: false)
    end

    def digest(value)
      Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(value.to_s), padding: false)
    end
  end

  def initialize(token, method:, url:)
    @token = token.to_s
    @method = method.to_s.upcase
    @url = url.to_s
  end

  def check!(access_token: nil)
    header, jwk = keyed

    @claims = verified(header, jwk)
    @jkt = self.class.thumbprint(jwk)

    matches!
    timely!
    bound!(access_token)
    once!

    self
  end

  private

    attr_reader :token, :method, :url, :claims

    def keyed
      held = JWT.decode(token, nil, false).last

      raise Refused, "a proof must be typed #{TYPE}" unless held["typ"].to_s.casecmp?(TYPE)

      algorithm = held["alg"].to_s

      raise Refused, "#{algorithm.presence || 'that'} is not an algorithm a proof may use" unless ALGORITHMS.include?(algorithm)

      jwk = held["jwk"]

      raise Refused, "a proof must carry the public key that signed it" unless jwk.is_a?(Hash)
      raise Refused, "a proof key must be public" if jwk.keys.any? { |field| SECRET.include?(field.to_s) }
      raise Refused, "a proof key must be public" if jwk["kty"].to_s == "oct"

      [ held, jwk ]
    rescue JWT::DecodeError
      raise Refused, "that proof is not a readable JWT"
    end

    def verified(header, jwk)
      JWT.decode(
        token, JWT::JWK.new(jwk).verify_key, true,
        algorithms: [ header["alg"].to_s ],
        verify_expiration: false
      ).first
    rescue JWT::DecodeError, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
      raise Refused, "that proof was not signed by the key it carries"
    end

    def matches!
      raise Refused, "a proof must name the method it is for" if claims["htm"].blank?
      raise Refused, "that proof was made for another method" unless claims["htm"].to_s.upcase == method

      held = claims["htu"].to_s

      raise Refused, "a proof must name the URL it is for" if held.blank?
      raise Refused, "that proof was made for another URL" unless tidied(held) == tidied(url)
    end

    def tidied(value)
      uri = URI.parse(value.to_s)
      uri.query = nil
      uri.fragment = nil
      uri.scheme = uri.scheme&.downcase
      uri.host = uri.host&.downcase
      uri.port = nil if uri.default_port == uri.port
      uri.path = "" if uri.path == "/"

      uri.to_s
    rescue URI::InvalidURIError
      raise Refused, "that proof names a URL this server cannot read"
    end

    def timely!
      held = claims["iat"]

      raise Refused, "a proof must say when it was made" unless held.is_a?(Numeric)

      made = Time.at(held).utc

      raise Refused, "that proof was made too long ago" if made < (WINDOW + LEEWAY).seconds.ago
      raise Refused, "that proof was made in the future" if made > LEEWAY.seconds.from_now
    end

    def bound!(access_token)
      return if access_token.blank?

      held = claims["ath"].to_s

      raise Refused, "a proof presented with a token must name it" if held.blank?

      unless ActiveSupport::SecurityUtils.secure_compare(held, self.class.digest(access_token))
        raise Refused, "that proof was made for another token"
      end
    end

    def once!
      held = claims["jti"]

      raise Refused, "a proof must carry a jti" if held.blank?

      key = "dpop:#{Current.tenant&.id}:#{jkt}:#{held}"

      unless Rails.cache.write(key, true, expires_in: MEMORY, unless_exist: true)
        raise Refused, "that proof has already been used"
      end
    end
end
