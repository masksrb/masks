module Masks
  module Client
    class Key
      CURVE = "prime256v1".freeze
      ALGORITHM = "ES256".freeze
      PUBLIC = %w[kty crv x y].freeze

      def self.generate
        new(OpenSSL::PKey::EC.generate(CURVE))
      end

      def self.parse(data)
        held = data.is_a?(String) && !data.lstrip.start_with?("{") ? OpenSSL::PKey.read(data) : imported(data)

        new(held)
      rescue OpenSSL::PKey::PKeyError, JSON::ParserError, JWT::JWKError, ArgumentError
        raise ArgumentError, "a key is a private P-256 key, as a PEM or a JWK"
      end

      def self.from(value)
        case value
        when self then value
        when OpenSSL::PKey::PKey then new(value)
        else parse(value)
        end
      end

      def self.imported(data)
        held = data.is_a?(String) ? JSON.parse(data) : data.to_h

        JWT::JWK.import(held.transform_keys(&:to_sym)).signing_key
      end

      def self.htu(url)
        uri = URI.parse(url.to_s)
        uri.query = nil
        uri.fragment = nil

        uri.to_s
      end

      attr_reader :private_key, :thumbprint

      def initialize(private_key)
        unless private_key.is_a?(OpenSSL::PKey::EC) && private_key.private? && private_key.group.curve_name == CURVE
          raise ArgumentError, "a key is a private P-256 key"
        end

        @private_key = private_key
        @public = JWT::JWK.new(private_key).export.transform_keys(&:to_s).slice(*PUBLIC).freeze
        @thumbprint = Proof.thumbprint(@public)
      end

      alias_method :kid, :thumbprint

      def public_jwk
        @public.merge("kid" => thumbprint, "alg" => ALGORITHM, "use" => "sig")
      end

      def jwks
        { "keys" => [ public_jwk ] }
      end

      def to_h
        JWT::JWK.new(private_key).export(include_private: true).transform_keys(&:to_s)
                .merge("kid" => thumbprint, "alg" => ALGORITHM, "use" => "sig")
      end

      def to_json(*)
        JSON.generate(to_h)
      end

      def to_pem
        private_key.private_to_pem
      end

      def inspect
        "#<#{self.class.name} #{thumbprint}>"
      end

      def sign(claims, header = {})
        JWT.encode(claims, private_key, ALGORITHM, header)
      end

      def proof(method, url, access_token: nil, nonce: nil)
        claims = {
          "jti" => SecureRandom.urlsafe_base64(24),
          "htm" => method.to_s.upcase,
          "htu" => self.class.htu(url),
          "iat" => Time.now.to_i
        }

        claims["ath"] = Proof.digest(access_token) unless access_token.to_s.empty?
        claims["nonce"] = nonce unless nonce.to_s.empty?

        sign(claims, { typ: Proof::TYPE, jwk: @public })
      end
    end
  end
end
