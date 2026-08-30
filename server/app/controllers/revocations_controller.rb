class RevocationsController < ApplicationController
  skip_forgery_protection

  def create
    client = authenticate_client!
    token = locate(params[:token], params[:token_type_hint])

    token.revoke! if token && token.client_id == client.id

    head :ok
  rescue Policy::Denied => denial
    render json: denial.to_h, status: denial.status
  end

  private

    def locate(secret, hint)
      return nil if secret.blank?

      case hint
      when "refresh_token" then RefreshToken.redeem(secret)
      when "access_token" then by_jwt(secret)
      else RefreshToken.redeem(secret) || by_jwt(secret)
      end
    end

    def by_jwt(token)
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
      id, secret = credentials
      client = Client.authenticating(id) if id.present?

      unless client&.authenticate_secret(secret)
        raise Policy::Denied.new(
          "invalid_client", "client authentication failed", status: :unauthorized
        )
      end

      client
    end

    def credentials
      header = request.authorization.to_s

      if header.start_with?("Basic ")
        Base64.decode64(header.split(" ", 2).last.to_s).split(":", 2).map { |p| CGI.unescape(p.to_s) }
      else
        [ params[:client_id], params[:client_secret] ]
      end
    end
end
