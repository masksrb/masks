module Masks
  module Openid
    class TokensController
      attr_reader :client

      def call(env)
        @tokens ||=
          Rack::OAuth2::Server::Token.new do |req, res|
            client = Masks.client(req.client_id)

            req.invalid_client! unless client.grant_types&.any?
            req.invalid_client! unless client&.valid_grant_type?(req.grant_type)
            req.invalid_client! unless client&.valid_secret?(req.client_secret)

            case req.grant_type
            when :client_credentials
              res.access_token = client.bearer_token!(scopes: req.scope)
            when :authorization_code
              code = Masks::AuthorizationCode.usable.find_by(secret: req.code)

              req.invalid_grant! unless code
              req.invalid_client! unless client.key == code.client&.key

              unless code&.valid_redirect_uri?(req.redirect_uri)
                req.invalid_grant!
              end

              if code.pkce?
                req.verify_code_verifier!(
                  code.code_challenge,
                  code.code_challenge_method,
                )
              end

              access_token = code.access_token
              res.access_token = access_token.to_bearer_token

              if code.openid?
                res.id_token =
                  Masks::IdToken.copy!(code).to_jwt(
                    access_token: res.access_token,
                    code: code.secret,
                  )
              end
            else
              req.unsupported_grant_type!
            end
          end
        @response ||= @tokens.call(env)
        @response
      end
    end
  end
end
