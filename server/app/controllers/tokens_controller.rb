class TokensController < ApplicationController
  include RackOAuth2Endpoint

  EXCHANGE = Rack::OAuth2::Server::Token::Extension::TokenExchange::GRANT_TYPE_URN
  DEVICE = Rack::OAuth2::Server::Token::Extension::DeviceCode::GRANT_TYPE_URN

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

        holding!(req, client)

        case req.grant_type.to_s
        when "authorization_code" then exchange_code(req, res, client)
        when "refresh_token" then refresh(req, res, client)
        when DEVICE then redeem_device(req, res, client)
        when EXCHANGE then exchange_token(req, res, client)
        else req.unsupported_grant_type!
        end
      end
    end

    def proof
      return @proof if defined?(@proof)

      @proof = Proof.presented?(request) ? Proof.read!(request) : nil
    end

    def jkt
      proof&.jkt
    end

    def holding!(req, client)
      proof

      if client.dpop_bound_access_tokens? && proof.nil?
        req.bad_request!(:invalid_dpop_proof, "this client has to hold its tokens to a key")
      end
    rescue Proof::Refused => refusal
      req.bad_request!(:invalid_dpop_proof, refusal.message)
    end

    def held!(req, token)
      return if token.nil? || !token.bound?

      unless token.bound_to?(proof)
        req.bad_request!(:invalid_dpop_proof, "that grant is held to a key this proof does not carry")
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
      code = AuthorizationCode.claim(req.code)

      if code.nil?
        AuthorizationCode.spent(req.code)&.revoke_issued!
        req.invalid_grant!("that code is not valid or has expired")
      end
      req.invalid_grant!("that code was issued to another client") if code.client_id != client.id

      unless code.redirect_uri == req.redirect_uri.to_s
        req.invalid_grant!("redirect_uri does not match the one the code was issued for")
      end

      unless code.verifies?(req.code_verifier)
        req.invalid_grant!("code_verifier does not match the challenge")
      end

      held!(req, code)

      audience = narrow(req, code.audience, client)
      access = AccessToken.issue!(
        issuer: issuer, actor: code.actor, client: client,
        scopes: code.scopes, audience: audience, parent: code,
        requested_claims: code.requested_claims, jkt: jkt
      )

      res.access_token = Payload.new(payload(access, code: code, client: client))
    end

    def refresh(req, res, client)
      held!(req, RefreshToken.redeem(req.refresh_token))

      token = RefreshToken.claim(req.refresh_token)

      if token.nil?
        replayed!(RefreshToken.spent(req.refresh_token), client)
        req.invalid_grant!("that refresh token is not valid or has expired")
      end

      req.invalid_grant!("that refresh token was issued to another client") if token.client_id != client.id

      held = token.bound? ? token.jkt : jkt
      scopes = req.scope.present? ? Scopes.granted(req.scope, token.scopes) : token.scope_list
      audience = narrow(req, token.audience, client)

      access = AccessToken.issue!(
        issuer: issuer, actor: token.actor, client: client,
        scopes: scopes, audience: audience, parent: token, jkt: held
      )

      rotated = RefreshToken.mint!(
        actor: token.actor, client: client, parent: token,
        scopes: Scopes.join(scopes), audience: audience, jkt: held,
        expires_at: RefreshToken.lifetime.from_now
      )

      res.access_token = Payload.new(
        "access_token" => access.jwt,
        "token_type" => access.token_type,
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(scopes),
        "refresh_token" => rotated.secret
      )
    end

    def replayed!(spent, client)
      return if spent.nil? || !spent.consumed?

      revoked = spent.revoke_family!

      Event.record!(
        Event::REFRESH_REUSED,
        actor: spent.actor, by: nil, client: client,
        issued_to: spent.client&.client_id, revoked: revoked
      )
    end

    def redeem_device(req, res, client)
      grant = DeviceGrant.spent(req.device_code)

      unless client.grants?(DeviceGrant::GRANT_TYPE)
        req.bad_request!(:unauthorized_client, "this client is not registered for the device grant")
      end

      if grant.nil? || grant.client_id != client.id
        req.invalid_grant!("that device code is not valid")
      end

      req.bad_request!(:access_denied, "the person turned this device away") if grant.denied?
      req.invalid_grant!("that device code has already been used") if grant.consumed?
      req.bad_request!(:expired_token, "that device code has expired") unless grant.live?

      hurried = grant.hurried?
      grant.polled!

      if hurried
        req.bad_request!(:slow_down, "poll no more often than every #{grant.interval} seconds")
      end

      unless grant.approved?
        req.bad_request!(:authorization_pending, "nobody has approved this device yet")
      end

      claimed = DeviceGrant.claim(req.device_code)

      req.invalid_grant!("that device code has already been used") if claimed.nil?

      res.access_token = Payload.new(granted(claimed, client))
    end

    def granted(grant, client)
      access = grant.issue!(issuer: issuer, jkt: jkt)

      body = {
        "access_token" => access.jwt,
        "token_type" => access.token_type,
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(access.scopes)
      }

      if access.scope_list.include?(Scopes::OPENID)
        body["id_token"] = issuer.id_token(
          actor: grant.actor, client: client,
          authenticated_at: grant.authenticated_at,
          amr: grant.held("amr"),
          access_token: access.jwt,
          sid: grant.session&.uuid
        )
      end

      if access.scope_list.include?(Scopes::OFFLINE)
        body["refresh_token"] = RefreshToken.mint!(
          actor: grant.actor, client: client, parent: grant,
          scopes: access.scopes, audience: access.audience, jkt: access.jkt,
          expires_at: RefreshToken.lifetime.from_now
        ).secret
      end

      body
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

      access = exchange.issue!(jkt: jkt)

      res.access_token = Payload.new(
        "access_token" => access.jwt,
        "issued_token_type" => Exchange::ACCESS_TOKEN,
        "token_type" => access.token_type,
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(access.scopes)
      )
    end

    def payload(access, code:, client:)
      body = {
        "access_token" => access.jwt,
        "token_type" => access.token_type,
        "expires_in" => access.expires_in,
        "scope" => Scopes.join(access.scopes)
      }

      if code.scope_list.include?(Scopes::OPENID)
        body["id_token"] = issuer.id_token(
          actor: code.actor, client: client, nonce: code.nonce,
          authenticated_at: code.authenticated_at,
          amr: (code.payload || {})["amr"],
          access_token: access.jwt,
          sid: code.session&.uuid
        )
      end

      if code.scope_list.include?(Scopes::OFFLINE)
        body["refresh_token"] = RefreshToken.mint!(
          actor: code.actor, client: client, parent: code,
          scopes: code.scopes, audience: access.audience, jkt: access.jkt,
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
