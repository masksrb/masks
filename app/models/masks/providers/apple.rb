module Masks
  module Providers
    class Apple < Abstract
      settings(
        pem: :string,
        key_id: :string,
        team_id: :string,
        scopes: :string,
        client_id: :string,
      )

      def omniauth_strategy
        OmniAuth::Strategies::Apple
      end

      def setup?
        setting(:client_id)&.present? && setting(:pem)&.present? &&
          setting(:key_id)&.present?
      end

      def omniauth_args
        [setting(:client_id), ""]
      end

      def omniauth_opts
        {
          scope: setting(:scopes, default: "email name"),
          team_id: setting(:team_id),
          key_id: setting(:key_id),
          pem: setting(:pem),
        }
      end
    end
  end
end
