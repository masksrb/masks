module Masks
  module Providers
    class Facebook < Abstract
      class << self
        def default_scopes
          "public_profile"
        end
      end

      include OauthProvider

      def omniauth_strategy
        OmniAuth::Strategies::Facebook
      end
    end
  end
end
