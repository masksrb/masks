module Masks
  module Client
    class IdToken
      REQUIRED = %w[iss sub aud exp iat].freeze

      class << self
        def verify(token, issuer:, client_id:, nonce: nil, access_token: nil, max_age: nil)
          claims = Verifier.new(issuer, audience: client_id).verify(token, required: REQUIRED, typ: Verifier::ID_TOKEN)

          raise InvalidToken.of("id_token_several_audiences") if Array(claims["aud"]).size > 1 && !claims.key?("azp")
          raise InvalidToken.of("id_token_other_client") if claims.key?("azp") && claims["azp"] != client_id
          raise InvalidToken.of("id_token_other_sign_in") if nonce && !same?(claims["nonce"], nonce)

          if access_token && claims.key?("at_hash") && !same?(claims["at_hash"], half_hash(access_token))
            raise InvalidToken.of("id_token_other_access_token")
          end

          Verifier.recent!(claims, max_age)
        end

        def half_hash(value)
          digest = Digest::SHA256.digest(value.to_s)

          Base64.urlsafe_encode64(digest[0, digest.bytesize / 2], padding: false)
        end

        private

          def same?(held, wanted)
            held.is_a?(String) && !held.empty? && OpenSSL.secure_compare(held, wanted.to_s)
          end
      end
    end
  end
end
