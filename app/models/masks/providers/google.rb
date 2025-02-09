module Masks
  module Providers
    class Google < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::GoogleOauth2
      end

      def identifier(auth_hash)
        auth_hash.dig("info", "email")
      end
    end
  end
end
