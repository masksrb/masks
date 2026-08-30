class UserinfoController < ApplicationController
  include BearerAuthentication

  skip_forgery_protection

  def show
    require_scope!(Scopes::OPENID)
    actor = access_token.actor

    raise Policy::Denied.new("invalid_token", "that token has no subject", status: :unauthorized) if actor.nil?

    render json: actor.claims(access_token.scopes)
  end
end
