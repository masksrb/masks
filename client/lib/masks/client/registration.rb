module Masks
  module Client
    class Registration
      attr_reader :issuer, :metadata, :access_token

      def self.create(issuer, token: nil, **attributes)
        issuer = Issuer.resolve(issuer)
        headers = token ? { "Authorization" => "Bearer #{token}" } : {}
        body = HTTP.post_json(endpoint(issuer, token), stringify(attributes), headers)

        new(issuer, body)
      end

      def self.endpoint(issuer, token)
        return issuer.endpoint("registration_endpoint") if token.nil? || issuer.discovery["registration_endpoint"]

        "#{issuer.url}/register"
      end

      def self.stringify(attributes)
        {
          "client_name" => attributes[:name] || attributes[:client_name],
          "redirect_uris" => Array(attributes[:redirect_uris]),
          "grant_types" => Array(attributes[:grant_types]),
          "response_types" => Array(attributes[:response_types]),
          "scope" => Array(attributes[:scope]).join(" "),
          "token_endpoint_auth_method" => attributes[:token_endpoint_auth_method],
          "application_type" => attributes[:application_type],
          "client_uri" => attributes[:client_uri],
          "logo_uri" => attributes[:logo_uri],
          "backchannel_logout_uri" => attributes[:backchannel_logout_uri],
          "jwks" => keyset(attributes[:jwks]),
          "dpop_bound_access_tokens" => attributes[:dpop_bound_access_tokens]
        }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def self.keyset(value)
        case value
        when nil then nil
        when Key then value.jwks
        when Array then { "keys" => value.map { |key| key.is_a?(Key) ? key.public_jwk : key } }
        else value
        end
      end

      def self.held(issuer, credentials)
        held = credentials.to_h.transform_keys(&:to_s)
        return nil if held["registration_client_uri"].blank? || held["registration_access_token"].blank?

        new(Issuer.resolve(issuer), held)
      end

      def initialize(issuer, body)
        @issuer = issuer
        @metadata = body
        @access_token = body["registration_access_token"]
      end

      def client_id
        metadata["client_id"]
      end

      def client_secret
        metadata["client_secret"]
      end

      def uri
        metadata["registration_client_uri"]
      end

      REFUSED = [ 401, 403 ].freeze
      GONE = (REFUSED + [ 404 ]).freeze

      def read
        still_ours(REFUSED) { HTTP.get(owned, authorization) }
      end

      def update(**attributes)
        @metadata = metadata.merge(
          still_ours(REFUSED) { HTTP.put_json(owned, self.class.stringify(attributes), authorization) }
        )
        self
      end

      def delete
        still_ours(GONE) { HTTP.delete(owned, authorization) }
        true
      end

      def known?
        read
        true
      rescue Unregistered
        false
      end

      def authorization
        { "Authorization" => "Bearer #{access_token}" }
      end

      def session(redirect_uri: nil, scope: Session::DEFAULT_SCOPE, **options)
        Session.new(
          issuer: issuer,
          client_id: client_id,
          client_secret: (client_secret unless options[:private_key]),
          redirect_uri: redirect_uri,
          scope: scope,
          **options
        )
      end

      private

        def owned
          return uri if Nonces.origin(uri) == Nonces.origin(issuer.url)

          raise Foreign, "the registration names #{Nonces.origin(uri)}, which is not #{issuer.url}"
        end

        def still_ours(statuses)
          yield
        rescue Unregistered
          raise
        rescue Refused => e
          raise unless statuses.include?(e.status)

          raise Unregistered.new(Unregistered::CODE, e.description, status: e.status)
        end
    end
  end
end
