module Masks
  module Providers
    module OAuthProvider
      extend ActiveSupport::Concern

      included do
        settings(client_id: :string, client_secret: :string, scopes: :string)
      end

      def setup?
        setting(:client_id)&.present? && setting(:client_secret)&.present?
      end

      def omniauth_args
        [setting(:client_id), setting(:client_secret)]
      end
    end
  end
end
