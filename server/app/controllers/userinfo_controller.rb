class UserinfoController < ApplicationController
  include RackOAuth2Endpoint
  include ResourceToken

  skip_forgery_protection

  def show
    with_access_token(scope: Scopes::OPENID) do |token|
      actor = token.actor

      next refuse_token("that token has no subject") if actor.nil?

      claims = actor.claims(
        token.scopes,
        requested: token.requested_claims,
        origin: issuer.url,
        subject: issuer.subject_for(actor, token.client)
      )
      standard = OpenIDConnect::ResponseObject::UserInfo.new(claims.symbolize_keys).as_json

      render json: standard.merge(claims.slice(Actor::AVATARS_CLAIM))
    end
  end
end
