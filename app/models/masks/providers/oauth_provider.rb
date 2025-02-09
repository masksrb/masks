module Masks
  module Providers
    module OauthProvider
      extend ActiveSupport::Concern

      included do
        setting :client_id, :string
        setting :client_secret, :string
        setting :scopes, [:string], default: self.default_scopes
      end

      class_methods do
        def default_scopes
          nil
        end
      end

      def setup?
        client_id&.present? && client_secret&.present?
      end

      def omniauth_args
        [client_id, client_secret]
      end

      def omniauth_opts
        { scope: scopes }
      end
    end
  end
end
