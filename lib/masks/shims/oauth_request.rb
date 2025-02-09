module Masks
  module Shims
    class OAuthRequest
      PARAMS = %w[
        client_id
        response_type
        grant_type
        redirect_uri
        code_challenge
        code_challenge_method
        login_hint
        prompt
        scope
        state
        nonce
      ]

      class << self
        def call(*args, **opts, &block)
          new(*args, **opts, &block).tap { |c| c.call }
        end
      end

      attr_accessor :client,
                    :scopes,
                    :req,
                    :res,
                    :params,
                    :error,
                    :internal_token

      def initialize(client, params, &block)
        @client = client
        @params = params&.stringify_keys || {}
        @block = block
        @app =
          Rack::OAuth2::Server::Authorize.new do |oidc_request, oidc_response|
            client_required! unless client

            @req = oidc_request
            @res = oidc_response

            @scopes = client.scope.minimum(req.scope)

            invalid_redirect_uri! unless req.redirect_uri

            if client.redirect_uris_a.none? && client.autofill_redirect_uri?
              client.redirect_uris = req.redirect_uri.to_s
              client.valid? || invalid_redirect_uri!
            end

            if client.valid_redirect_uri?(req.redirect_uri)
              res.redirect_uri =
                req.verified_redirect_uri = req.redirect_uri.to_s
            else
              invalid_redirect_uri!
            end

            if res.protocol_params_location == :fragment && req.nonce.blank?
              nonce_required!
            end

            response_type =
              Array(req.response_type).collect(&:to_s).sort.join(" ")

            unless client.valid_response_type?(response_type)
              unsupported_response_type!
            end

            unless client.valid_pkce_request?(
                     response_type:,
                     challenge: req.try(:code_challenge),
                     method: req.try(:code_challenge_method),
                   )
              pkce_required!
            end

            @block.call(self) if @block
          end
      end

      def approved?
        !error && @approved
      end

      def denied?
        error
      end

      def denied!
        self.error = "access-denied"
        req.access_denied!
      end

      def original_redirect_uri
        req&.redirect_uri&.to_s
      end

      def redirect_uri
        return unless @response

        _status, header, = @response

        header["Location"]
      end

      def call
        return if error || @response

        @response ||= @app.call(Masks.env.rack(:get, "/", params))
      rescue Rack::OAuth2::Server::Authorize::BadRequest => e
        invalid_response!
      end

      def validate_scopes!(actor)
        scopes_required! unless actor.scopes?(*scopes)
      end

      def approve!(actor:, **opts)
        @approved = true

        validate_scopes!(actor)

        client.save if client.redirect_uris_changed?

        response_types = Array(req.response_type)

        if response_types.include? :code
          res.code =
            if client.internal?
              @internal_token =
                Masks::InternalToken.create!(
                  client:,
                  nonce: req.nonce,
                  redirect_uri: res.redirect_uri,
                  scopes: scopes.join(" "),
                  actor:,
                  **opts,
                )

              @internal_token.code
            else
              @authorization_code =
                Masks::AuthorizationCode.create!(
                  client:,
                  nonce: req.nonce,
                  redirect_uri: res.redirect_uri,
                  code_challenge: req.try(:code_challenge),
                  code_challenge_method: req.try(:code_challenge_method),
                  scopes: scopes.join(" "),
                  actor:,
                  **opts,
                )

              @authorization_code.code
            end
        end

        if response_types.include? :token
          @access_token =
            Masks::AccessToken.create!(
              client:,
              nonce: req.nonce,
              redirect_uri: res.redirect_uri,
              scopes: scopes.join(" "),
              actor:,
              **opts,
            )

          res.access_token = @access_token.to_bearer_token
        end

        if response_types.include? :id_token
          @id_token =
            Masks::IdToken.create!(
              client:,
              nonce: req.nonce,
              redirect_uri: res.redirect_uri,
              scopes: scopes.join(" "),
              actor:,
              **opts,
            )

          res.id_token =
            @id_token.to_jwt(
              code: (res.respond_to?(:code) ? res.code : nil),
              access_token:
                (res.respond_to?(:access_token) ? res.access_token : nil),
            )
        end

        res.approve!
      end

      private

      def scopes_required!
        self.error = "missing-scopes"
        req.invalid_request! "scopes required"
      end

      def client_required!
        self.error = "missing-client"
        req.invalid_client!
        req.invalid_request! "nonce required"
      end

      def nonce_required!
        self.error = "missing-nonce"
        req.invalid_request! "nonce required"
      end

      def pkce_required!
        self.error = "invalid-pkce"
        req.invalid_request! "invalid PKCE request"
      end

      def invalid_redirect_uri!
        self.error = "invalid-redirect"
        req.invalid_request!("invalid redirect_uri")
      end

      def unsupported_response_type!
        invalid_response!
        req&.unsupported_response_type!
      end

      def invalid_response!
        self.error = "invalid-response"
      end
    end
  end
end
