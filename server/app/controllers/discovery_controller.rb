class DiscoveryController < ApplicationController
  def openid
    render json: issuer.discovery
  end

  def jwks
    expires_in 5.minutes, public: true
    render json: issuer.jwks
  end
end
