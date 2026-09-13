module Masks
  module Client
    class Delegations
      SCOPE = "masks:delegate:".freeze
      UPSTREAM_ACCESS_TOKEN = "urn:masks:params:oauth:token-type:upstream_access_token".freeze
      REFUSALS = %w[invalid_grant insufficient_scope invalid_target unauthorized_client access_denied
                    login_required interaction_required consent_required invalid_scope].freeze

      class Refused < Error
        attr_reader :code, :description, :secret

        def initialize(code, description, secret: nil)
          super([ code, description ].compact.join(": "))

          @code = code
          @description = description
          @secret = secret
        end

        def signed_in_again?
          %w[login_required interaction_required].include?(code)
        end
      end

      class Unavailable < Error
        attr_reader :secret

        def initialize(message, secret: nil)
          super(message)

          @secret = secret
        end
      end

      Held = Struct.new(:connection, :provider, :provider_name, :label, :subject, :secret, keyword_init: true)

      Upstream = Struct.new(:access_token, :expires_at, :scope, :secret, keyword_init: true) do
        def expired?(leeway: 60)
          Time.now.to_i + leeway >= expires_at.to_i
        end
      end

      attr_reader :issuer, :client_id, :client_secret, :redirect_uri

      def initialize(issuer:, client_id:, client_secret:, redirect_uri:)
        @issuer = Issuer.resolve(issuer)
        @client_id = client_id
        @client_secret = client_secret
        @redirect_uri = redirect_uri
      end

      def start(provider:, prompt: nil, max_age: nil, state: SecureRandom.urlsafe_base64(24))
        started = session.start(scope: [ "openid", "offline_access", "#{SCOPE}#{provider}" ], prompt: prompt, state: state)
        url = max_age ? "#{started[:url]}&#{URI.encode_www_form('max_age' => max_age.to_i)}" : started[:url]

        { "url" => url, "state" => started[:state], "verifier" => started[:verifier], "provider" => provider.to_s }
      end

      def finish(params:, started:)
        params = params.to_h.transform_keys(&:to_s)
        started = started.to_h.transform_keys(&:to_s)

        raise Refused.new(params["error"], params["error_description"]) if params["error"].to_s != ""

        unless params["state"].to_s != "" && secure_compare(params["state"].to_s, started["state"].to_s)
          raise Refused.new("invalid_state", "the state did not match the one this connection started with")
        end

        body = token_request([ [ "grant_type", "authorization_code" ], [ "code", params["code"].to_s ],
                               [ "redirect_uri", redirect_uri ], [ "code_verifier", started["verifier"].to_s ] ])

        held = Array(body["delegations"]).find { |one| one["provider"] == started["provider"] }

        raise Refused.new("access_denied", "masks connected nothing for #{started['provider']}") if held.nil?
        raise Refused.new("invalid_grant", "masks issued no refresh token to keep the connection with") if body["refresh_token"].to_s == ""

        Held.new(
          connection: held["connection"], provider: held["provider"], provider_name: held["provider_name"],
          label: held["label"], subject: held["subject"], secret: body["refresh_token"]
        )
      end

      def token(secret, connection:)
        refreshed = token_request([ [ "grant_type", "refresh_token" ], [ "refresh_token", secret.to_s ] ])
        rotated = refreshed["refresh_token"].to_s == "" ? secret : refreshed["refresh_token"]

        released = token_request([
          [ "grant_type", Tokens::EXCHANGE ],
          [ "subject_token", refreshed["access_token"].to_s ],
          [ "subject_token_type", Tokens::ACCESS_TOKEN ],
          [ "requested_token_type", UPSTREAM_ACCESS_TOKEN ],
          [ "audience", connection.to_s ]
        ], secret: rotated)

        Upstream.new(
          access_token: released["access_token"],
          expires_at: Time.now.to_i + released["expires_in"].to_i,
          scope: released["scope"].to_s,
          secret: rotated
        )
      end

      private

        def session
          @session ||= Session.new(issuer: issuer, client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri)
        end

        def token_request(form, secret: nil)
          body = HTTP.post_form(issuer.endpoint("token_endpoint"), form + credentials)

          raise Refused.new(body["error"], body["error_description"], secret: secret) if body["error"]
          raise Refused.new("invalid_token_response", "masks answered without an access token", secret: secret) if body["access_token"].to_s == ""

          body
        rescue Unregistered
          raise
        rescue Rejected => e
          raise Unavailable.new("masks answered #{e.status}: #{e.message}", secret: secret) if unavailable?(e)

          raise Refused.new(e.code, e.description, secret: secret)
        rescue Unreachable => e
          raise Unavailable.new(e.message, secret: secret)
        end

        def unavailable?(rejection)
          return false if REFUSALS.include?(rejection.code)

          rejection.code == "temporarily_unavailable" || rejection.status.to_i >= 500 || rejection.status.to_i == 429
        end

        def credentials
          [ [ "client_id", client_id ], [ "client_secret", client_secret ] ].reject { |_, value| value.nil? }
        end

        def secure_compare(given, expected)
          return false unless given.bytesize == expected.bytesize

          OpenSSL.fixed_length_secure_compare(given, expected)
        end
    end
  end
end
