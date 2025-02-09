module Masks
  module Providers
    class Facebook < Abstract
      include OAuthProvider

      def omniauth_strategy
        OmniAuth::Strategies::Facebook
      end

      def omniauth_opts
        { scope: setting(:scopes, default: "public_profile") }
      end
    end
  end
end
