module Masks
  module Server
    class Authorization
      attr_reader :client_id, :redirect_uri, :response_type, :state, :nonce,
                  :code_challenge, :code_challenge_method, :prompt, :audience,
                  :requested_scopes, :max_age, :acr_values, :organization, :requested_claims, :request_uri,
                  :user_code, :dpop_jkt, :request_object, :saml

      def self.from_request(request)
        repeated = Rack::Utils.parse_query(request.query_string)
        repeated = repeated.merge(Rack::Utils.parse_query(request.raw_post)) { |_, a, b| Array(a) + Array(b) } if request.post?
        params = request.params

        new(
          client_id: params["client_id"],
          redirect_uri: params["redirect_uri"],
          response_type: params["response_type"],
          scope: params["scope"],
          state: params["state"],
          nonce: params["nonce"],
          code_challenge: params["code_challenge"],
          code_challenge_method: params["code_challenge_method"],
          prompt: params["prompt"],
          max_age: params["max_age"],
          acr_values: params["acr_values"],
          organization: params["organization"],
          resource: repeated["resource"],
          request: params["request"],
          request_uri: params["request_uri"],
          claims: params["claims"],
          authorization_details: params["authorization_details"],
          dpop_jkt: params["dpop_jkt"]
        )
      end

      def initialize(client_id:, redirect_uri:, response_type:, scope: nil, state: nil,
                     nonce: nil, code_challenge: nil, code_challenge_method: nil,
                     prompt: nil, max_age: nil, acr_values: nil, organization: nil, resource: nil, request: nil,
                     request_uri: nil, claims: nil, authorization_details: nil, user_code: nil, dpop_jkt: nil,
                     signed: false, saml: nil)
        @signed = signed
        @authorization_details_value = authorization_details.presence
        @saml = saml.presence
        @dpop_jkt = dpop_jkt.presence
        @user_code = user_code.presence
        @requested_claims = self.class.parse_claims(claims)
        @request_object = request.presence
        @request_uri = request_uri.presence
        @client_id = client_id.to_s
        @redirect_uri = redirect_uri.to_s
        @response_type = response_type.to_s
        @requested_scopes = Scopes.list(scope)
        @state = state
        @nonce = nonce
        @code_challenge = code_challenge.presence
        @code_challenge_method = (code_challenge_method.presence || ("S256" if @code_challenge))
        @prompt = Scopes.list(prompt)
        @max_age = max_age.presence&.to_i
        @acr_values = Scopes.list(acr_values)
        @organization = organization.to_s.strip.downcase.presence
        @audience = Array(resource).map(&:to_s).reject(&:empty?).uniq
      end

      def client
        @client ||= Client.authenticating(client_id, protocol: saml? ? SamlIdentity::PROTOCOL : Client::OIDC)
      end

      def saml?
        @saml.present?
      end

      def authorization_details
        return @authorization_details if defined?(@authorization_details)

        @authorization_details = AuthorizationDetails.parse(@authorization_details_value)
      end

      def authorization_details_json
        authorization_details&.canonical
      rescue AuthorizationDetails::Invalid
        value = @authorization_details_value

        value.is_a?(String) ? value : value.to_json
      end

      def granted_scopes
        @granted_scopes ||= client ? client.permitted_scopes(requested_scopes) : []
      end

      def scopes_for(actor)
        return granted_scopes if actor.nil?

        actor.permitted_scopes(granted_scopes)
      end

      def self.parse_claims(value)
        return value if value.is_a?(Hash)
        return nil if value.blank?

        parsed = JSON.parse(value.to_s)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      def request_object?
        @request_object.present?
      end

      def request_uri?
        @request_uri.present?
      end

      def signed?
        @signed
      end

      def reauthenticate?
        prompt.include?("login")
      end

      def multi_factor?
        [ acr_values, claimed_acr_values ].any? do |accepted|
          (accepted & Issuer::ACR_VALUES) == [ Issuer::ACR_MULTI_FACTOR ]
        end
      end

      def consent?
        prompt.include?("consent") || device?
      end

      def silent?
        prompt.include?("none")
      end

      def validate!
        AuthorizationPolicy.new(self).call
        self
      end

      def redirect_with(issuer:, **params)
        uri = URI.parse(redirect_uri)
        query = Rack::Utils.parse_query(uri.query)
        query.merge!(params.transform_keys(&:to_s).compact)
        query["state"] = state if state.present?
        query["iss"] = issuer.url
        uri.query = Rack::Utils.build_query(query)
        uri.to_s
      end

      def canonical
        {
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "response_type" => response_type,
          "scope" => Scopes.join(requested_scopes),
          "state" => state,
          "nonce" => nonce,
          "code_challenge" => code_challenge,
          "code_challenge_method" => code_challenge_method,
          "prompt" => prompt.sort.join(" ").presence,
          "max_age" => max_age,
          "acr_values" => acr_values.join(" ").presence,
          "organization" => organization,
          "resource" => audience.sort,
          "claims" => requested_claims&.to_json,
          "authorization_details" => authorization_details_json,
          "dpop_jkt" => dpop_jkt
        }.compact
      end

      def device?
        user_code.present?
      end

      def claimed_acr_values
        wanted = requested_claims&.dig("id_token", "acr")

        return [] unless wanted.is_a?(Hash)

        Array(wanted["values"]) + Array(wanted["value"])
      end

      def fingerprint
        Digest::SHA256.hexdigest(canonical.merge("user_code" => user_code, "saml" => saml).compact.to_json)
      end

      def to_params
        canonical.reject { |_, value| value.blank? }
      end

      def query_pairs
        pairs = canonical.except("resource").reject { |_, value| value.blank? }.to_a

        audience.each { |value| pairs << [ "resource", value ] }
        pairs
      end
    end
  end
end
