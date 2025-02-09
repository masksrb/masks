# frozen_string_literal: true

module Masks
  class AccessToken < Token
    validates :actor_id, presence: true, if: -> { type == "Masks::AccessToken" }

    cleanup :expires_at do
      0.seconds
    end

    def bearer_token?
      true
    end

    def to_bearer_token
      Rack::OAuth2::AccessToken::Bearer.new(
        access_token: secret,
        expires_in: (expires_at - Time.now.utc).to_i,
      )
    end
  end
end
