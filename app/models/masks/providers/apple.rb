module Masks
  module Providers
    class Apple < Abstract
      setting :pem, :string
      setting :key_id, :string
      setting :team_id, :string
      setting :scopes, :string
      setting :client_id, :string
      setting :scopes, :string, default: "email name"

      def omniauth_strategy
        OmniAuth::Strategies::Apple
      end

      def setup?
        client_id && pem && key_id
      end

      def omniauth_args
        [client_id, ""]
      end

      def omniauth_opts
        { scope: scopes, team_id:, key_id:, pem: }
      end
    end
  end
end
