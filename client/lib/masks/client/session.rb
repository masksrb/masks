module Masks
  module Client
    class Session
      DEFAULT_SCOPE = %w[openid profile email].freeze
      ORGANIZATION = "organization".freeze
      ORGANIZATION_KEY = /\A[a-z0-9][a-z0-9-]*\z/

      def self.organization_key(value)
        key = value.to_s.strip.downcase

        key.match?(ORGANIZATION_KEY) ? key : nil
      end
      ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
      ASSERTION_LIFETIME = 60

      NO_NONCE = "use_dpop_nonce".freeze

      attr_reader :issuer, :client_id, :client_secret, :redirect_uri, :scope, :private_key, :key_id, :dpop

      def initialize(issuer:, client_id:, redirect_uri: nil, client_secret: nil, private_key: nil, key_id: nil,
                     dpop: nil, scope: DEFAULT_SCOPE)
        raise ArgumentError, "a client authenticates with a secret or a private key, not both" if client_secret && private_key

        @issuer = Issuer.resolve(issuer)
        @client_id = client_id
        @client_secret = client_secret
        @private_key = private_key.is_a?(Key) ? private_key.private_key : private_key
        @private_key = OpenSSL::PKey.read(@private_key) if @private_key.is_a?(String)
        @key_id = key_id || (private_key.thumbprint if private_key.is_a?(Key))
        @dpop = dpop && Key.from(dpop)
        @redirect_uri = redirect_uri
        @scope = Array(scope)
      end

      def start(resource: nil, prompt: nil, scope: nil, state: SecureRandom.urlsafe_base64(24),
                nonce: SecureRandom.urlsafe_base64(24), max_age: nil, organization: nil)
        pkce = Pkce.generate
        scopes = Array(scope || self.scope)
        organization = Session.organization_key(organization)
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
        pairs << [ "organization", organization ] if organization

        {
          url: "#{issuer.endpoint('authorization_endpoint')}?#{URI.encode_www_form(pairs)}",
          state: state,
          nonce: nonce,
          verifier: pkce.verifier,
          max_age: max_age&.to_i
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

        token(form)
      end

      def client_credentials(scope: nil, resource: nil)
        form = [ [ "grant_type", "client_credentials" ], [ "client_id", client_id ] ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        token(form)
      end

      def enroll(scope:, name: nil, expires_in: nil)
        form = [ [ "client_id", client_id ], [ "scope", Array(scope).join(" ") ] ]

        form << [ "client_name", name ] if name
        form << [ "expires_in", expires_in.to_i ] if expires_in

        Enrollment.issued(post("enrollment_endpoint", form))
      end

      def unenroll(machine_id)
        url = "#{issuer.endpoint('enrollment_endpoint')}/#{URI.encode_www_form_component(machine_id)}"

        HTTP.delete_form(url, [ [ "client_id", client_id ] ] + assertion, authorization)
        true
      end

      def refresh(refresh_token, resource: nil, scope: nil)
        form = [
          [ "grant_type", "refresh_token" ],
          [ "refresh_token", refresh_token ],
          [ "client_id", client_id ]
        ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        token(form)
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

        token(form)
      end

      def device_authorization(scope: nil, resource: nil)
        form = [ [ "client_id", client_id ] ]

        form << [ "scope", Array(scope).join(" ") ] if scope
        Array(resource).each { |value| form << [ "resource", value ] }

        Device.issued(post("device_authorization_endpoint", form))
      end

      def await_device(device, pause: Device::INTERVAL)
        form = [ [ "grant_type", Device::GRANT_TYPE ], [ "device_code", device.device_code ], [ "client_id", client_id ] ]
        interval = device.interval.positive? ? device.interval : pause

        loop do
          raise Rejected.new("expired_token", "the code expired before anyone approved it") if device.expired?

          sleep(interval)

          begin
            return token(form)
          rescue Rejected => e
            case e.code
            when "authorization_pending" then next
            when "slow_down" then interval += pause
            else raise
            end
          end
        end
      end

      def transport(*origins, tokens: nil, scope: nil, resource: nil, &keep)
        Transport.new(*origins, tokens: tokens, key: dpop) do |held|
          renewed = tokens ? renew(held, scope: scope, resource: resource) : client_credentials(scope: scope, resource: resource)

          keep&.call(renewed)
          renewed
        end
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

      def userinfo(tokens)
        url = issuer.endpoint("userinfo_endpoint")

        return HTTP.get(url, "Authorization" => "Bearer #{tokens}") unless tokens.is_a?(Tokens)
        return HTTP.get(url, "Authorization" => "Bearer #{tokens.access_token}") unless tokens.bound?

        HTTP.parse(Transport.new(url, tokens: tokens, key: dpop).request("GET", url, limit: HTTP::READ_LIMIT))
      end

      # The person the +tokens+ belong to: the ID token's claims merged over
      # userinfo. With +max_age+, the seconds the app asked for when it started
      # the sign-in, an ID token whose +auth_time+ is missing or older than
      # that, plus 30 seconds of leeway, raises InvalidToken.
      def identity(tokens, max_age: nil)
        return nil if tokens.id_token.nil?

        claims = Verifier.recent!(Verifier.new(issuer, audience: client_id).verify(tokens.id_token), max_age)

        profile(tokens).merge(claims)
      end

      def profile(tokens)
        return {} if tokens.access_token.nil?

        userinfo(tokens)
      rescue Masks::Client::Error
        {}
      end

      private

        def renew(held, scope:, resource:)
          if held&.refresh_token.to_s.empty?
            raise Rejected.new("invalid_grant", "there is no refresh token to renew these tokens with")
          end

          renewed = refresh(held.refresh_token, scope: scope, resource: resource)

          return renewed if renewed.refresh_token

          Tokens.from_h(renewed.to_h.merge("refresh_token" => held.refresh_token))
        end

        def token(form)
          tokens = Tokens.granted(dpop ? proven(issuer.endpoint("token_endpoint"), form) : post("token_endpoint", form))

          if dpop && !tokens.bound?
            raise Rejected.new("invalid_dpop_proof", "the token endpoint answered with a token that is not held to this key")
          end

          tokens
        end

        def post(endpoint, form)
          url = issuer.endpoint(endpoint)

          HTTP.post_form(url, form + assertion, authorization)
        end

        def proven(url, form)
          nonce = issuer.nonces[url]
          response = HTTP.deliver(proven_request(url, form, nonce))
          wanted = issuer.nonces.learn(url, response)

          begin
            HTTP.parse(response)
          rescue Rejected => e
            raise unless e.code == NO_NONCE && wanted && wanted != nonce

            response = HTTP.deliver(proven_request(url, form, wanted))
            issuer.nonces.learn(url, response)

            HTTP.parse(response)
          end
        end

        def proven_request(url, form, nonce)
          headers = authorization.merge("DPoP" => dpop.proof("POST", url, nonce: nonce))

          HTTP.form_request(Net::HTTP::Post, url, form + assertion, headers)
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
