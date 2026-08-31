module Masks
  module Client
    class Session
      DEFAULT_SCOPE = %w[openid profile email].freeze

      attr_reader :issuer, :client_id, :client_secret, :redirect_uri, :scope

      def initialize(issuer:, client_id:, redirect_uri:, client_secret: nil, scope: DEFAULT_SCOPE)
        @issuer = Issuer.resolve(issuer)
        @client_id = client_id
        @client_secret = client_secret
        @redirect_uri = redirect_uri
        @scope = Array(scope)
      end

      def start(resource: nil, prompt: nil, scope: nil, state: SecureRandom.urlsafe_base64(24),
                nonce: SecureRandom.urlsafe_base64(24))
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

        Tokens.granted(HTTP.post_form(issuer.endpoint("token_endpoint"), form, authorization))
      end

      def refresh(refresh_token, resource: nil, scope: nil)
        form = [
          [ "grant_type", "refresh_token" ],
          [ "refresh_token", refresh_token ],
          [ "client_id", client_id ]
        ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(HTTP.post_form(issuer.endpoint("token_endpoint"), form, authorization))
      end

      def exchange(subject_token, scope: nil, resource: nil, lifetime: nil)
        form = [
          [ "grant_type", Tokens::EXCHANGE ],
          [ "client_id", client_id ],
          [ "subject_token", subject_token ],
          [ "subject_token_type", Tokens::ACCESS_TOKEN ]
        ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        form << [ "requested_lifetime", lifetime.to_i ] if lifetime
        Array(resource).each { |value| form << [ "resource", value ] }

        Tokens.granted(HTTP.post_form(issuer.endpoint("token_endpoint"), form, authorization))
      end

      def revoke(token, hint: nil)
        form = [ [ "token", token ], [ "client_id", client_id ] ]
        form << [ "token_type_hint", hint ] if hint

        HTTP.post_form(issuer.endpoint("revocation_endpoint"), form, authorization)
        true
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
          HTTP.post_form(issuer.endpoint("introspection_endpoint"), form, authorization)
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
