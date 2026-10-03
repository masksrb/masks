module Masks
  module Client
    class Proof
      class Invalid < Error; end

      SCHEME = "DPoP".freeze
      TYPE = "dpop+jwt".freeze
      ALGORITHMS = %w[ES256 ES384 ES512 PS256 PS384 PS512 RS256].freeze
      SECRET = %w[d p q dp dq qi k].freeze
      THUMBED = { "EC" => %w[crv kty x y], "RSA" => %w[e kty n] }.freeze
      LEEWAY = 30
      WINDOW = 60
      MEMORY = WINDOW + (LEEWAY * 2)

      class Memory
        def initialize
          @held = {}
          @lock = Mutex.new
        end

        def first?(key, expires_in:)
          now = Time.now.to_f

          @lock.synchronize do
            @held.delete_if { |_, until_at| until_at < now }
            return false if @held.key?(key)

            @held[key] = now + expires_in
            true
          end
        end
      end

      def self.thumbprint(jwk)
        named = THUMBED[jwk["kty"]] || raise(Invalid, "the proof key is of a kind this resource does not read")
        held = named.to_h { |field| [ field, jwk[field] ] }

        raise Invalid, "the proof key is missing part of itself" if held.any? { |_, value| value.to_s.empty? }

        digest(JSON.generate(held))
      end

      def self.digest(value)
        Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(value.to_s), padding: false)
      end

      def initialize(proof, method:, url:, replay: nil)
        held = proof.to_s.split(",").map(&:strip).reject(&:empty?)

        raise Invalid, "exactly one DPoP proof is required" unless held.size == 1

        @proof = held.first
        @method = method.to_s.upcase
        @url = url.to_s
        @replay = replay
      end

      def check!(access_token:, jkt:)
        header = keyed
        claims = verified(header)
        thumbprint = self.class.thumbprint(header["jwk"])

        raise Invalid, "that proof was made with another key than the token is bound to" unless same?(thumbprint, jkt)

        matches!(claims)
        timely!(claims)
        raise Invalid, "that proof was made for another token" unless same?(claims["ath"].to_s, self.class.digest(access_token))

        once!(claims, thumbprint)

        self
      end

      private

        def keyed
          header = JWT.decode(@proof, nil, false).last

          raise Invalid, "a proof must be typed #{TYPE}" unless header["typ"].to_s.casecmp?(TYPE)
          raise Invalid, "#{header['alg'] || 'that'} is not an algorithm a proof may use" unless ALGORITHMS.include?(header["alg"].to_s)

          jwk = header["jwk"]

          raise Invalid, "a proof must carry the public key that signed it" unless jwk.is_a?(Hash)
          raise Invalid, "a proof key must be public" if jwk["kty"].to_s == "oct" || jwk.keys.any? { |field| SECRET.include?(field.to_s) }

          header
        rescue JWT::DecodeError
          raise Invalid, "that proof is not a readable JWT"
        end

        def verified(header)
          JWT.decode(@proof, JWT::JWK.new(header["jwk"]).verify_key, true,
                     algorithms: [ header["alg"].to_s ], verify_expiration: false).first
        rescue JWT::DecodeError, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
          raise Invalid, "that proof was not signed by the key it carries"
        end

        def matches!(claims)
          raise Invalid, "that proof was made for another method" unless claims["htm"].to_s.upcase == @method
          raise Invalid, "that proof was made for another URL" unless tidied(claims["htu"]) == tidied(@url)
        end

        def tidied(value)
          uri = URI.parse(value.to_s)
          raise Invalid, "that proof names no URL" if uri.host.nil?

          port = ":#{uri.port}" unless uri.port.nil? || uri.port == uri.default_port
          path = uri.path.to_s == "/" ? "" : uri.path.to_s

          "#{uri.scheme.to_s.downcase}://#{uri.host.downcase}#{port}#{path}"
        rescue URI::InvalidURIError
          raise Invalid, "that proof names a URL this resource cannot read"
        end

        def timely!(claims)
          made = claims["iat"]

          raise Invalid, "a proof must say when it was made" unless made.is_a?(Numeric)
          raise Invalid, "that proof was made too long ago" if made < Time.now.to_i - WINDOW - LEEWAY
          raise Invalid, "that proof was made in the future" if made > Time.now.to_i + LEEWAY
        end

        def once!(claims, thumbprint)
          jti = claims["jti"].to_s

          raise Invalid, "a proof must carry a jti" if jti.empty?
          return if @replay.nil? || @replay.first?("#{thumbprint}:#{jti}", expires_in: MEMORY)

          raise Invalid, "that proof has already been used"
        end

        def same?(held, expected)
          !held.to_s.empty? && held.bytesize == expected.to_s.bytesize &&
            OpenSSL.fixed_length_secure_compare(held, expected.to_s)
        end
    end
  end
end
