module Masks
  module Client
    class Registration
      attr_reader :issuer, :metadata, :access_token

      def self.create(issuer, token: nil, **attributes)
        issuer = Issuer.resolve(issuer)
        headers = token ? { "Authorization" => "Bearer #{token}" } : {}
        body = HTTP.post_json(
          issuer.endpoint("registration_endpoint"), stringify(attributes), headers
        )

        new(issuer, body)
      end

      def self.stringify(attributes)
        {
          "client_name" => attributes[:name] || attributes[:client_name],
          "redirect_uris" => Array(attributes[:redirect_uris]),
          "grant_types" => fallback(attributes[:grant_types], %w[authorization_code]),
          "response_types" => fallback(attributes[:response_types], %w[code]),
          "scope" => Array(attributes[:scope]).join(" "),
          "token_endpoint_auth_method" => attributes[:token_endpoint_auth_method],
          "application_type" => attributes[:application_type],
          "client_uri" => attributes[:client_uri],
          "logo_uri" => attributes[:logo_uri]
        }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def self.fallback(value, default)
        list = Array(value)
        list.empty? ? default : list
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

      def read
        HTTP.get(uri, authorization)
      end

      def update(**attributes)
        @metadata = metadata.merge(HTTP.put_json(uri, self.class.stringify(attributes), authorization))
        self
      end

      def delete
        HTTP.delete(uri, authorization)
        true
      end

      def authorization
        { "Authorization" => "Bearer #{access_token}" }
      end

      def session(redirect_uri:, scope: Session::DEFAULT_SCOPE)
        Session.new(
          issuer: issuer,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          scope: scope
        )
      end
    end
  end
end
