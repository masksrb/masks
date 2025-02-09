module Masks
  module Providers
    class Twitter < Abstract
      def self.default_scopes
        "tweet.read users.read"
      end

      include OauthProvider

      def omniauth_strategy
        OmniAuth::Strategies::Twitter2
      end

      def identifier(auth_hash)
        "@#{auth_hash.dig("info", "nickname")}"
      end
    end
  end
end
