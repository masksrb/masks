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
        started = session.start(scope: [ "openid", "offline_access", "#{SCOPE}#{provider}" ], prompt: prompt,
                                max_age: max_age, state: state)

        { "url" => started[:url], "state" => started[:state], "verifier" => started[:verifier], "provider" => provider.to_s }
      end

      def finish(params:, started:)
        params = params.to_h.transform_keys(&:to_s)
        started = started.to_h.transform_keys(&:to_s)

        raise Refused.new(params["error"], params["error_description"]) if params["error"].to_s != ""

        unless params["state"].to_s != "" && OpenSSL.secure_compare(params["state"].to_s, started["state"].to_s)
          raise Refused.new("invalid_state", "the state did not match the one this connection started with")
        end

        tokens = answered { session.complete(code: params["code"].to_s, verifier: started["verifier"].to_s) }
        held = tokens.delegations.find { |one| one["provider"] == started["provider"] }

        raise Refused.new("access_denied", "masks connected nothing for #{started['provider']}") if held.nil?
        raise Refused.new("invalid_grant", "masks issued no refresh token to keep the connection with") if tokens.refresh_token.to_s == ""

        Held.new(
          connection: held["connection"], provider: held["provider"], provider_name: held["provider_name"],
          label: held["label"], subject: held["subject"], secret: tokens.refresh_token
        )
      end

      def token(secret, connection:)
        refreshed = answered { session.refresh(secret.to_s) }
        rotated = refreshed.refresh_token.to_s == "" ? secret : refreshed.refresh_token

        released = answered(secret: rotated) do
          session.exchange(refreshed.access_token, requested_token_type: UPSTREAM_ACCESS_TOKEN, audience: connection.to_s)
        end

        Upstream.new(access_token: released.access_token, expires_at: released.expires_at, scope: released.scope, secret: rotated)
      end

      private

        def session
          @session ||= Session.new(issuer: issuer, client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri)
        end

        def answered(secret: nil)
          yield
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
    end
  end
end
