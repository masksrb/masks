module Masks
  module Providers
    class Twitter < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::Twitter2
      end

      def omniauth_opts
        { scope: setting(:scopes, default: "tweet.read users.read") }
      end

      def identifier(auth_hash)
        "@#{auth_hash.dig("info", "nickname")}"
      end
    end
  end
end
