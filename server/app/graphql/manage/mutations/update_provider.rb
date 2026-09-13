module Manage
  module Mutations
    class UpdateProvider < BaseMutation
      argument :key, ID
      argument :name, String, required: false
      argument :protocol, String, required: false
      argument :authorization_url, String, required: false
      argument :token_url, String, required: false
      argument :client_id, String, required: false
      argument :client_secret, String, required: false
      argument :userinfo_url, String, required: false
      argument :emails_url, String, required: false
      argument :claims, GraphQL::Types::JSON, required: false
      argument :token_auth_method, String, required: false
      argument :response_mode, String, required: false
      argument :team_id, String, required: false
      argument :key_id, String, required: false
      argument :private_key, String, required: false
      argument :scopes, [ String ], required: false
      argument :authorize_params, GraphQL::Types::JSON, required: false
      argument :subject_claim, String, required: false
      argument :issuer, String, required: false
      argument :jwks_uri, String, required: false
      argument :role, String, required: false
      argument :trusts_email, Boolean, required: false
      argument :email_domains, [ String ], required: false
      argument :signup_scopes, [ String ], required: false

      field :provider, Types::ProviderType, null: false

      def resolve(key:, scopes: nil, authorize_params: nil, client_secret: nil, private_key: nil,
                  email_domains: nil, signup_scopes: nil, **attributes)
        provider = provider!(key)

        provider.assign_attributes(attributes)
        provider.scopes = Scopes.join(scopes) unless scopes.nil?
        provider.authorize_params = authorize_params unless authorize_params.nil?
        provider.client_secret = client_secret if client_secret.present?
        provider.private_key = private_key if private_key.present?
        provider.email_domains = ProviderDomains.join(email_domains) unless email_domains.nil?
        provider.signup_scopes = Scopes.join(signup_scopes) unless signup_scopes.nil?
        provider.assign_attributes(jwks: {}, jwks_fetched_at: nil) if provider.jwks_uri_changed? || provider.issuer_changed?

        save!(provider)
        audit!(
          ::Event::PROVIDER_UPDATED,
          provider: provider.key,
          changed: changed(attributes, scopes, client_secret, private_key, email_domains, signup_scopes)
        )

        { provider: provider }
      end

      private

        def changed(attributes, scopes, client_secret, private_key, email_domains, signup_scopes)
          held = attributes.keys.map(&:to_s)
          held << "scopes" unless scopes.nil?
          held << "email_domains" unless email_domains.nil?
          held << "signup_scopes" unless signup_scopes.nil?
          held << "client_secret" if client_secret.present?
          held << "private_key" if private_key.present?

          held
        end
    end
  end
end
