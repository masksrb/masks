module Masks
  module Client
    class Handshake
      PATH = "/handshake".freeze
      GRANT_TYPES = %w[authorization_code refresh_token].freeze
      AUTH_METHOD = "client_secret_basic".freeze

      attr_reader :issuer, :name, :resource, :redirect_uris, :scope, :return_to

      def initialize(issuer, name:, resource:, redirect_uris:, return_to:,
                     scope: Session::DEFAULT_SCOPE)
        @issuer = Issuer.resolve(issuer)
        @name = name.to_s
        @resource = resource.to_s
        @redirect_uris = Array(redirect_uris).map(&:to_s)
        @scope = Array(scope).flat_map { |value| value.to_s.split(/\s+/) }.reject(&:empty?)
        @return_to = return_to.to_s
      end

      def endpoint
        @endpoint ||= advertised || "#{issuer.url}#{PATH}"
      end

      def start(state: SecureRandom.urlsafe_base64(32))
        { url: url(state: state), state: state }
      end

      def url(state:)
        query = [
          [ "client_name", name ],
          [ "resource", resource ],
          [ "scope", scope.join(" ") ],
          [ "return_to", return_to ],
          [ "state", state ]
        ]

        redirect_uris.each { |uri| query << [ "redirect_uris", uri ] }

        "#{endpoint}?#{URI.encode_www_form(query)}"
      end

      def complete(params, state:)
        held = normalize(params)

        refuse(held["error"], held["error_description"]) if present?(held["error"])
        verify_state!(held["state"], state)
        verify_issuer!(held["iss"])

        redeem(held["initial_access_token"])
      end

      def redeem(token)
        unless present?(token)
          refuse("invalid_request", "the handshake came back without a token")
        end

        Registration.create(
          issuer,
          token: token,
          name: name,
          redirect_uris: redirect_uris,
          grant_types: GRANT_TYPES,
          scope: scope,
          token_endpoint_auth_method: AUTH_METHOD
        )
      end

      private

        def advertised
          value = issuer.discovery["handshake_endpoint"]
          present?(value) ? value.to_s : nil
        rescue Masks::Client::Error
          nil
        end

        def verify_state!(returned, held)
          return if present?(held) && present?(returned) &&
                    OpenSSL.secure_compare(returned.to_s, held.to_s)

          refuse("invalid_state", "the handshake did not match this browser")
        end

        def verify_issuer!(named)
          return unless present?(named)
          return if Issuer.normalize(named) == issuer.url

          refuse("invalid_issuer", "that came back from #{named} rather than #{issuer.url}")
        end

        def refuse(code, description)
          raise Rejected.new(code.to_s, description.to_s)
        end

        def normalize(params)
          params.to_h.each_with_object({}) { |(key, value), held| held[key.to_s] = value }
        end

        def present?(value)
          !value.nil? && !value.to_s.empty?
        end
    end
  end
end
