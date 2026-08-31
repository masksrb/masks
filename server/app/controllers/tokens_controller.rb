class TokensController < ApplicationController
  include RackOAuth2Endpoint

  EXCHANGE = Rack::OAuth2::Server::Token::Extension::TokenExchange::GRANT_TYPE_URN

  skip_forgery_protection

  rate_limit to: 60, within: 1.minute,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { slow_down }

  def create
    return unsupported_grant_type unless Client::GRANT_TYPES.include?(params[:grant_type].to_s)

    render_rack(endpoint.call(request.env))
  end

  private

    def endpoint
      Rack::OAuth2::Server::Token.new do |req, res|
        client = authenticate_client!(req)

        case req.grant_type.to_s
        when "authorization_code" then exchange_code(req, res, client)
        when "refresh_token" then refresh(req, res, client)
        when EXCHANGE then exchange_token(req, res, client)
        else req.unsupported_grant_type!
        end
      end
    end

    def unsupported_grant_type
      render json: {
        "error" => "unsupported_grant_type",
        "error_description" => "this server does not support that grant_type"
      }, status: :bad_request
    end

    def slow_down
      render json: {
        "error" => "slow_down",
        "error_description" => "too many token requests from this address"
      }, status: :too_many_requests
    end

    def exchange_code(req, res, client)
      code = AuthorizationCode.redeem(req.code)

      if code.nil?
        AuthorizationCode.spent(req.code)&.revoke_issued!
        req.invalid_grant!("that code is not valid or has expired")
      end
      req.invalid_grant!("that code was issued to another client") if code.client_id != client.id

      unless code.redirect_uri == req.redirect_uri.to_s
        req.invalid_grant!("redirect_uri does not match the one the code was issued for")
      end

      code.consume!

      unless code.verifies?(req.code_verifier)
        req.invalid_grant!("code_verifier does not match the challenge")
      end

      audience = narrow(req, code.audience, client)
      access = AccessToken.issue!(
        issuer: issuer, actor: code.actor, client: client,
        scopes: code.scopes, audience: audience, parent: code,
        requested_claims: code.requested_claims
      )

      res.access_token = Payload.new(payload(access, code: code, client: client))
    end

    def refresh(req, res, client)
      token = RefreshToken.redeem(req.refresh_token)

      req.invalid_grant!("that refresh token is not valid or has expired") if token.nil?
      req.invalid_grant!("that refresh token was issued to another client") if token.client_id != client.id

      token.consume!

      scopes = req.scope.present? ? Scopes.granted(req.scope, token.scopes) : token.scope_list
      audience = narrow(req, token.audience, client)

      access = AccessToken.issue!(
        issuer: issuer, actor: token.actor, client: client,
        scopes: scopes, audience: audience
      )

      rotated = RefreshToken.mint!(
        actor: token.actor, client: client, parent: token,
        scopes: Scopes.join(scopes), audience: audience,
        expires_at: RefreshToken.lifetime.from_now
      )

      res.access_token = Payload.new(
        "access_token" => access.jwt,
        "token_type" => "Bearer",
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(scopes),
        "refresh_token" => rotated.secret
      )
    end

    def exchange_token(req, res, client)
      exchange = Exchange.new(
        client: client,
        issuer: issuer,
        subject_token: req.subject_token,
        subject_token_type: req.subject_token_type,
        requested_token_type: req.requested_token_type,
        scope: req.scope,
        resource: repeated("resource"),
        lifetime: req.requested_lifetime
      ).validate!

      access = exchange.issue!

      res.access_token = Payload.new(
        "access_token" => access.jwt,
        "issued_token_type" => Exchange::ACCESS_TOKEN,
        "token_type" => "Bearer",
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(access.scopes)
      )
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
          actor: code.actor, client: client, nonce: code.nonce,
          authenticated_at: code.authenticated_at,
          access_token: access.jwt
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

    def narrow(req, granted, client)
      requested = repeated("resource")

      return granted.presence || [ client.client_id ] if requested.empty?

      refused = requested - granted

      if granted.any? && refused.any?
        req.bad_request!(:invalid_target, "resource was not authorized: #{refused.join(', ')}")
      end

      requested
    end

    def authenticate_client!(req)
      req.invalid_client!("client_id is required") if req.client_id.blank?

      client = Client.authenticating(req.client_id)

      req.invalid_client!("no client is registered with that client_id") if client.nil?

      unless client.authenticate_secret(req.client_secret)
        req.invalid_client!("client authentication failed")
      end

      client
    end
end
