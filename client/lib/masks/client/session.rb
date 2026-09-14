module Masks
  module Client
    class Session
      DEFAULT_SCOPE = %w[openid profile email].freeze
      ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
      ASSERTION_LIFETIME = 60

      attr_reader :issuer, :client_id, :client_secret, :redirect_uri, :scope, :private_key, :key_id

      def initialize(issuer:, client_id:, redirect_uri: nil, client_secret: nil, private_key: nil, key_id: nil,
                     scope: DEFAULT_SCOPE)
        raise ArgumentError, "a client authenticates with a secret or a private key, not both" if client_secret && private_key

        @issuer = Issuer.resolve(issuer)
        @client_id = client_id
        @client_secret = client_secret
        @private_key = private_key.is_a?(String) ? OpenSSL::PKey.read(private_key) : private_key
        @key_id = key_id
        @redirect_uri = redirect_uri
        @scope = Array(scope)
      end

      def start(resource: nil, prompt: nil, scope: nil, state: SecureRandom.urlsafe_base64(24),
                nonce: SecureRandom.urlsafe_base64(24), max_age: nil)
        pkce = Pkce.generate
        scopes = Array(scope || self.scope)
        nonce = nil unless scopes.include?("openid")

        pairs = [
          [ "response_type", "code" ],
          [ "client_id", client_id ],
          [ "redirect_uri", redirect_uri ],
          [ "scope", scopes.join(" ") ],
          [ "state", state ],
          [ "code_challenge", pkce.challenge ],
          [ "code_challenge_method", pkce.method ]
        ]

        pairs << [ "nonce", nonce ] if nonce

        Array(resource).each { |value| pairs << [ "resource", value ] }
        pairs << [ "prompt", prompt ] if prompt
        pairs << [ "max_age", max_age.to_i ] if max_age

        {
          url: "#{issuer.endpoint('authorization_endpoint')}?#{URI.encode_www_form(pairs)}",
          state: state,
          nonce: nonce,
          verifier: pkce.verifier
        }
      end

      def complete(code:, verifier:, resource: nil)
        form = [
          [ "grant_type", "authorization_code" ],
          [ "code", code ],
          [ "client_id", client_id ],
          [ "redirect_uri", redirect_uri ],
          [ "code_verifier", verifier ]
        ]

        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(post("token_endpoint", form))
      end

      def client_credentials(scope: nil, resource: nil)
        form = [ [ "grant_type", "client_credentials" ], [ "client_id", client_id ] ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(post("token_endpoint", form))
      end

      def refresh(refresh_token, resource: nil, scope: nil)
        form = [
          [ "grant_type", "refresh_token" ],
          [ "refresh_token", refresh_token ],
          [ "client_id", client_id ]
        ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(post("token_endpoint", form))
      end

      def exchange(subject_token, scope: nil, resource: nil, lifetime: nil, requested_token_type: nil, audience: nil,
                   subject_token_type: Tokens::ACCESS_TOKEN, actor_token: nil, actor_token_type: Tokens::ACCESS_TOKEN)
        form = [
          [ "grant_type", Tokens::EXCHANGE ],
          [ "client_id", client_id ],
          [ "subject_token", subject_token ],
          [ "subject_token_type", subject_token_type ]
        ]

        form.push([ "actor_token", actor_token ], [ "actor_token_type", actor_token_type ]) if actor_token

        form << [ "requested_token_type", requested_token_type ] if requested_token_type
        Array(audience).each { |value| form << [ "audience", value ] }

        form << [ "scope", Array(scope).join(" ") ] if scope
        form << [ "requested_lifetime", lifetime.to_i ] if lifetime
        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(post("token_endpoint", form))
      end

      def revoke(token, hint: nil)
        form = [ [ "token", token ], [ "client_id", client_id ] ]
        form << [ "token_type_hint", hint ] if hint

        post("revocation_endpoint", form)
        true
      end

      def logout_token(token)
        Logout.verify(token, issuer: issuer, audience: client_id)
      end

      def end_session_url(post_logout_redirect_uri: nil, state: nil, id_token_hint: nil)
        pairs = [ [ "client_id", client_id ] ]
        pairs << [ "id_token_hint", id_token_hint ] if id_token_hint
        pairs << [ "post_logout_redirect_uri", post_logout_redirect_uri ] if post_logout_redirect_uri
        pairs << [ "state", state ] if state

        "#{issuer.endpoint('end_session_endpoint')}?#{URI.encode_www_form(pairs)}"
      end

      def introspect(token, hint: nil)
        form = [ [ "token", token ], [ "client_id", client_id ] ]
        form << [ "token_type_hint", hint ] if hint

        Introspection.new(
          post("introspection_endpoint", form)
        )
      end

      def userinfo(access_token)
        HTTP.get(issuer.endpoint("userinfo_endpoint"), "Authorization" => "Bearer #{access_token}")
      end

      def identity(tokens)
        return nil if tokens.id_token.nil?

        claims = Verifier.new(issuer, audience: client_id).verify(tokens.id_token)

        profile(tokens).merge(claims)
      end

      def profile(tokens)
        return {} if tokens.access_token.nil?

        userinfo(tokens.access_token)
      rescue Masks::Client::Error
        {}
      end

      private

        def post(endpoint, form)
          url = issuer.endpoint(endpoint)

          HTTP.post_form(url, form + assertion, authorization)
        end

        def assertion
          return [] if private_key.nil?

          now = Time.now.to_i
          claims = {
            "iss" => client_id, "sub" => client_id, "aud" => issuer.url,
            "iat" => now, "exp" => now + ASSERTION_LIFETIME, "jti" => SecureRandom.uuid
          }
          header = key_id ? { kid: key_id } : {}

          [
            [ "client_assertion_type", ASSERTION_TYPE ],
            [ "client_assertion", JWT.encode(claims, private_key, signing_algorithm, header) ]
          ]
        end

        def signing_algorithm
          return "RS256" if private_key.is_a?(OpenSSL::PKey::RSA)

          { "prime256v1" => "ES256", "secp384r1" => "ES384", "secp521r1" => "ES512" }.fetch(private_key.group.curve_name) do
            raise ArgumentError, "#{private_key.group.curve_name} is not a curve masks checks assertions for"
          end
        end

        def authorization
          return {} if client_secret.nil?

          encoded = Base64.strict_encode64(
            "#{URI.encode_www_form_component(client_id)}:#{URI.encode_www_form_component(client_secret)}"
          )

          { "Authorization" => "Basic #{encoded}" }
        end
    end
  end
end
