module Manage
  module Mutations
    class UpdateProvider < BaseMutation
      argument :key, ID
      argument :name, String, required: false
      argument :authorization_url, String, required: false
      argument :token_url, String, required: false
      argument :client_id, String, required: false
      argument :client_secret, String, required: false
      argument :revocation_url, String, required: false
      argument :userinfo_url, String, required: false
      argument :scopes, [ String ], required: false
      argument :authorize_params, GraphQL::Types::JSON, required: false
      argument :subject_claim, String, required: false
      argument :label_claim, String, required: false

      field :provider, Types::ProviderType, null: false

      def resolve(key:, scopes: nil, authorize_params: nil, client_secret: nil, **attributes)
        provider = provider!(key)

        provider.assign_attributes(attributes)
        provider.scopes = Scopes.join(scopes) unless scopes.nil?
        provider.authorize_params = authorize_params unless authorize_params.nil?
        provider.client_secret = client_secret if client_secret.present?

        save!(provider)
        audit!(::Event::PROVIDER_UPDATED, provider: provider.key, changed: changed(attributes, scopes, client_secret))

        { provider: provider }
      end

      private

        def changed(attributes, scopes, client_secret)
          held = attributes.keys.map(&:to_s)
          held << "scopes" unless scopes.nil?
          held << "client_secret" if client_secret.present?

          held
        end
    end
  end
end
