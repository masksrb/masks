module Federation
  class Oidc < Protocol
    SKEW = 60
    JWKS_INTERVAL = 5.minutes
    ALGORITHMS = %w[RS256 RS384 RS512 ES256 ES384 ES512 PS256 PS384 PS512].freeze
    NAMED = %w[given_name family_name].freeze

    def refresh_keys!
      endpoint = provider.jwks_uri.presence || Provider.discover(provider.issuer)["jwks_uri"]

      raise Provider::Untrusted, "#{provider.name} publishes no jwks_uri" if endpoint.blank?

      fetched = provider.get(endpoint)

      raise Provider::Untrusted, "#{provider.name} published no keys" unless fetched["keys"].is_a?(Array) && fetched["keys"].any?

      provider.update!(jwks: fetched, jwks_uri: endpoint, jwks_fetched_at: Time.current)

      fetched
    end

    private

      def extra_handoff
        { "nonce" => SecureRandom.urlsafe_base64(STATE_BYTES) }
      end

      def scopes
        Scopes.union(provider.form_post? ? %w[openid] : %w[openid email profile], provider.scope_list)
      end

      def identify(tokens, handoff, params)
        raise Provider::Untrusted, "#{provider.name} returned no id_token" if tokens["id_token"].blank?

        claims = verify(tokens["id_token"])

        unless claims["iss"].to_s.chomp("/") == provider.issuer
          raise Provider::Untrusted, "#{provider.name} answered for #{claims['iss']}, not #{provider.issuer}"
        end

        raise Provider::Untrusted, "#{provider.name} issued that token to another application" unless audience_holds?(claims)
        raise Provider::Untrusted, "#{provider.name} returned a token for a different sign-in" unless handoff["nonce"].present? && claims["nonce"] == handoff["nonce"]
        raise Provider::Untrusted, "#{provider.name} returned no subject" if claims["sub"].blank?

        named(fill(claims, tokens), params)
      end

      def audience_holds?(claims)
        audience = Array(claims["aud"])

        return false unless audience.include?(provider.client_id)
        return true if audience.length == 1

        claims["azp"].present? ? claims["azp"] == provider.client_id : false
      end

      def fill(claims, tokens)
        return claims if provider.userinfo_url.blank? || claims["email"].present?

        profile = provider.get(provider.userinfo_url, tokens["access_token"]).except("iss", "aud", "exp", "iat", "nonce")

        return claims unless profile["sub"].present? && profile["sub"] == claims["sub"]

        profile.merge(claims)
      rescue Provider::Refused, Provider::Unreachable
        claims
      end

      def named(claims, params)
        user = JSON.parse(params["user"].to_s)
        name = user.is_a?(Hash) ? user["name"] : nil

        return claims unless name.is_a?(Hash)

        given = name["firstName"].to_s.strip.presence
        family = name["lastName"].to_s.strip.presence

        claims.reverse_merge(
          "given_name" => given,
          "family_name" => family,
          "name" => [ given, family ].compact.join(" ").presence
        ).compact
      rescue JSON::ParserError
        claims
      end

      def verify(id_token)
        keys = held_keys
        kid = peek(id_token)["kid"]

        keys = refresh_keys! if stale_keys?(keys, kid)

        decode(id_token, keys)
      rescue JWT::VerificationError, JWT::DecodeError => e
        raise Provider::Untrusted, "#{provider.name} signed that token with a key this server could not verify (#{e.class})"
      end

      def decode(id_token, keys)
        JWT.decode(
          id_token, nil, true,
          algorithms: ALGORITHMS,
          jwks: JWT::JWK::Set.new(keys),
          verify_expiration: true,
          verify_iat: true,
          exp_leeway: SKEW,
          iat_leeway: SKEW,
          nbf_leeway: SKEW
        ).first
      end

      def held_keys
        held = provider.jwks.is_a?(Hash) ? provider.jwks : {}

        held["keys"].is_a?(Array) ? held : { "keys" => [] }
      end

      def stale_keys?(keys, kid)
        return false if provider.jwks_fetched_at.present? && provider.jwks_fetched_at > JWKS_INTERVAL.ago && keys["keys"].any?
        return true if keys["keys"].empty?

        kid.blank? || keys["keys"].none? { |key| key["kid"] == kid }
      end

      def peek(id_token)
        header = id_token.to_s.split(".").first

        JSON.parse(Base64.urlsafe_decode64(header.to_s + "=" * ((4 - header.to_s.length % 4) % 4)))
      rescue ArgumentError, JSON::ParserError
        {}
      end
  end
end
