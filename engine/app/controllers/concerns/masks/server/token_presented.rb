module Masks
  module Server
    module TokenPresented
      extend ActiveSupport::Concern

      include ClientAuthentication

      included do
        skip_forgery_protection

        rescue_from Policy::Denied, with: :client_denied
      end

      private

        def refuse!(description)
          raise Policy::Denied.new("invalid_request", description, status: :bad_request)
        end

        def no_store!
          response.headers["Cache-Control"] = "no-store"
          response.headers["Pragma"] = "no-cache"
        end

        def presented_token(secret = params[:token], hint = params[:token_type_hint])
          return nil if secret.blank?

          case hint
          when "refresh_token" then RefreshToken.redeem(secret)
          when "access_token" then access_token_from(secret)
          else RefreshToken.redeem(secret) || access_token_from(secret)
          end
        end

        def access_token_from(token)
          claims = AccessToken.decode(token, issuer: issuer, verify_expiration: false, required: %w[iss jti])

          AccessToken.find_by(digest: claims["jti"])
        rescue JWT::DecodeError
          nil
        end

        def authenticate_client!
          authenticated_client
        end

        def client_denied(denial)
          render json: denial.to_h, status: denial.status
        end
    end
  end
end
