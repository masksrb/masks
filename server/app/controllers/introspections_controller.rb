class IntrospectionsController < ApplicationController
  include TokenPresented

  INACTIVE = { "active" => false }.freeze

  rate_limit to: 120, within: 1.minute,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { render json: INACTIVE, status: :too_many_requests }

  def create
    client = authenticate_client!
    token = presented_token

    return render json: INACTIVE unless token&.live? && entitled?(client, token)

    render json: described(token)
  end

  private

    def entitled?(client, token)
      return true if token.client_id == client.id

      (Array(token.audience) & Array(client.resources)).any?
    end

    def described(token)
      {
        "active" => true,
        "scope" => Scopes.join(token.scopes),
        "client_id" => token.client&.client_id,
        "username" => token.actor&.nickname,
        "token_type" => token.is_a?(AccessToken) ? "Bearer" : nil,
        "exp" => token.expires_at.to_i,
        "iat" => token.created_at.to_i,
        "sub" => Subjects.for(token.actor, token.client),
        "aud" => token.audience.presence,
        "iss" => issuer.url,
        "jti" => token.digest,
        "tenant" => current_tenant.to_identity
      }.compact
    end
end
