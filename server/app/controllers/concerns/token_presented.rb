module TokenPresented
  extend ActiveSupport::Concern

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
      claims = JWT.decode(
        token, nil, true,
        algorithms: [ SigningKey::ALGORITHM ],
        jwks: issuer.jwks,
        iss: issuer.url, verify_iss: true,
        verify_expiration: false,
        required_claims: %w[iss jti]
      ).first

      AccessToken.find_by(digest: claims["jti"])
    rescue JWT::DecodeError
      nil
    end

    def authenticate_client!
      id, secret = client_credentials
      client = Client.authenticating(id) if id.present?

      unless client&.authenticate_secret(secret)
        raise Policy::Denied.new(
          "invalid_client", "client authentication failed", status: :unauthorized
        )
      end

      client
    end

    def client_credentials
      header = request.authorization.to_s

      if header.start_with?("Basic ")
        Base64.decode64(header.split(" ", 2).last.to_s).split(":", 2).map { |p| CGI.unescape(p.to_s) }
      else
        [ params[:client_id], params[:client_secret] ]
      end
    end

    def client_denied(denial)
      render json: denial.to_h, status: denial.status
    end
end
