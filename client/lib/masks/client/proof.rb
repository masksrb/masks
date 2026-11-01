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
          @swept = 0.0
        end

        def first?(key, expires_in:)
          now = Time.now.to_f

          @lock.synchronize do
            sweep(now) if now - @swept > 1
            return false if @held.key?(key) && @held[key] >= now

            @held[key] = now + expires_in
            true
          end
        end

        private

          def sweep(now)
            @held.delete_if { |_, until_at| until_at < now }
            @swept = now
          end
      end

      MEMORY_LOCK = Mutex.new

      def self.memory
        MEMORY_LOCK.synchronize { @memory ||= Memory.new }
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

        raise Invalid, Masks::Client.saying("one_proof") unless held.size == 1

        @proof = held.first
        @method = method.to_s.upcase
        @url = url.to_s
        @replay = replay
      end

      def check!(access_token:, jkt:)
        header = keyed
        claims = verified(header)
        thumbprint = self.class.thumbprint(header["jwk"])

        raise Invalid, Masks::Client.saying("proof_other_key") unless same?(thumbprint, jkt)

        matches!(claims)
        timely!(claims)
        raise Invalid, Masks::Client.saying("proof_other_token") unless same?(claims["ath"].to_s, self.class.digest(access_token))

        once!(claims, thumbprint)

        self
      end

      private

        def keyed
          header = JWT.decode(@proof, nil, false).last

          raise Invalid, Masks::Client.saying("proof_type", TYPE) unless header["typ"].to_s.casecmp?(TYPE)
          raise Invalid, Masks::Client.saying("proof_algorithm", header["alg"] || "that") unless ALGORITHMS.include?(header["alg"].to_s)

          jwk = header["jwk"]

          raise Invalid, Masks::Client.saying("proof_no_key") unless jwk.is_a?(Hash)
          raise Invalid, Masks::Client.saying("proof_key_private") if jwk["kty"].to_s == "oct" || jwk.keys.any? { |field| SECRET.include?(field.to_s) }

          header
        rescue JWT::DecodeError
          raise Invalid, Masks::Client.saying("proof_not_a_jwt")
        end

        def verified(header)
          JWT.decode(@proof, JWT::JWK.new(header["jwk"]).verify_key, true,
                     algorithms: [ header["alg"].to_s ], verify_expiration: false).first
        rescue JWT::DecodeError, JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError
          raise Invalid, Masks::Client.saying("proof_unsigned")
        end

        def matches!(claims)
          raise Invalid, Masks::Client.saying("proof_other_method") unless claims["htm"].to_s.upcase == @method
          raise Invalid, Masks::Client.saying("proof_other_url") unless tidied(claims["htu"]) == tidied(@url)
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
          raise Invalid, Masks::Client.saying("proof_not_now") if made < Time.now.to_i - WINDOW - LEEWAY || made > Time.now.to_i + LEEWAY
        end

        def once!(claims, thumbprint)
          jti = claims["jti"].to_s

          raise Invalid, Masks::Client.saying("proof_no_jti") if jti.empty?
          return if @replay.nil? || first?("#{thumbprint}:#{jti}")

          raise Invalid, Masks::Client.saying("proof_replayed")
        end

        def first?(key)
          @replay.first?(key, expires_in: MEMORY)
        rescue StandardError => e
          raise ReplayUnavailable, "the replay store could not say whether that proof is new (#{e.class})"
        end

        def same?(held, expected)
          !held.to_s.empty? && held.bytesize == expected.to_s.bytesize &&
            OpenSSL.fixed_length_secure_compare(held, expected.to_s)
        end
    end
  end
end
