class UserinfoController < ApplicationController
  include RackOAuth2Endpoint
  include BearerResource

  skip_forgery_protection

  def show
    with_access_token(scope: Scopes::OPENID) do |token|
      actor = token.actor

      next refuse_token("that token has no subject") if actor.nil?

      render json: OpenIDConnect::ResponseObject::UserInfo.new(
        actor.claims(token.scopes, requested: token.requested_claims).symbolize_keys
      ).as_json
    end
  end
end
