class DiscoveryController < ApplicationController
  def openid
    render json: issuer.discovery
  end

  def jwks
    expires_in 5.minutes, public: true
    render json: issuer.jwks
  end

  def resource
    render json: issuer.protected_resource
  end
end
