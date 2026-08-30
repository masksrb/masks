class TokensController < ApplicationController
  skip_forgery_protection

  def create
    case params[:grant_type]
    when "authorization_code" then exchange_code
    when "refresh_token" then refresh
    else
      deny("unsupported_grant_type", "grant_type must be authorization_code or refresh_token")
    end
  rescue Policy::Denied => denial
    render json: denial.to_h, status: denial.status
  end

  private

    def exchange_code
      client = authenticate_client!
      code = AuthorizationCode.redeem(params[:code])

      return deny("invalid_grant", "that code is not valid or has expired") if code.nil?
      return deny("invalid_grant", "that code was issued to another client") if code.client_id != client.id

      unless code.redirect_uri == params[:redirect_uri].to_s
        return deny("invalid_grant", "redirect_uri does not match the one the code was issued for")
      end

      unless code.verifies?(params[:code_verifier])
        return deny("invalid_grant", "code_verifier does not match the challenge")
      end

      code.consume!

      audience = narrow(code.audience, client)
      access = AccessToken.issue!(
        issuer: issuer, actor: code.actor, client: client,
        scopes: code.scopes, audience: audience
      )

      render json: payload(access, code: code, client: client)
    end

    def refresh
      client = authenticate_client!
      token = RefreshToken.redeem(params[:refresh_token])

      return deny("invalid_grant", "that refresh token is not valid or has expired") if token.nil?
      return deny("invalid_grant", "that refresh token was issued to another client") if token.client_id != client.id

      token.consume!

      scopes = params[:scope].present? ? Scopes.granted(params[:scope], token.scopes) : token.scope_list
      audience = narrow(token.audience, client)

      access = AccessToken.issue!(
        issuer: issuer, actor: token.actor, client: client,
        scopes: scopes, audience: audience
      )

      rotated = RefreshToken.mint!(
        actor: token.actor, client: client, parent: token,
        scopes: Scopes.join(scopes), audience: audience,
        expires_at: RefreshToken.lifetime.from_now
      )

      render json: {
        "access_token" => access.jwt,
        "token_type" => "Bearer",
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(scopes),
        "refresh_token" => rotated.secret
      }
    end

    def payload(access, code:, client:)
      body = {
        "access_token" => access.jwt,
        "token_type" => "Bearer",
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(access.scopes)
      }

      if code.scope_list.include?(Scopes::OPENID)
        body["id_token"] = issuer.id_token(
          actor: code.actor, client: client,
          scopes: code.scopes, nonce: code.nonce
        )
      end

      if code.scope_list.include?(Scopes::OFFLINE)
        body["refresh_token"] = RefreshToken.mint!(
          actor: code.actor, client: client, parent: code,
          scopes: code.scopes, audience: access.audience,
          expires_at: RefreshToken.lifetime.from_now
        ).secret
      end

      body
    end

    def narrow(granted, client)
      requested = Rack::Utils.parse_query(request.raw_post)["resource"]
      requested = Array(requested).map(&:to_s).reject(&:empty?)

      return granted.presence || [ client.client_id ] if requested.empty?

      refused = requested - granted
      deny!("invalid_target", "resource was not authorized: #{refused.join(', ')}") if granted.any? && refused.any?

      requested
    end

    def authenticate_client!
      id, secret = credentials
      deny!("invalid_client", "client_id is required", status: :unauthorized) if id.blank?

      client = Client.authenticating(id)
      deny!("invalid_client", "no client is registered with that client_id", status: :unauthorized) if client.nil?

      unless client.authenticate_secret(secret)
        deny!("invalid_client", "client authentication failed", status: :unauthorized)
      end

      client
    end

    def credentials
      header = request.authorization.to_s

      if header.start_with?("Basic ")
        decoded = Base64.decode64(header.split(" ", 2).last.to_s)
        decoded.split(":", 2).map { |part| CGI.unescape(part.to_s) }
      else
        [ params[:client_id], params[:client_secret] ]
      end
    end

    def deny(error, description, status: :bad_request)
      render json: { "error" => error, "error_description" => description }, status: status
    end

    def deny!(error, description, status: :bad_request)
      raise Policy::Denied.new(error, description, status: status)
    end
end
