module Manage
  module Mutations
    class CreateProvider < BaseMutation
      argument :key, ID
      argument :name, String
      argument :preset, ID, required: false
      argument :preset_values, GraphQL::Types::JSON, required: false
      argument :protocol, String, required: false
      argument :authorization_url, String, required: false
      argument :token_url, String, required: false
      argument :client_id, String, required: false
      argument :client_secret, String, required: false
      argument :userinfo_url, String, required: false
      argument :emails_url, String, required: false
      argument :scopes, [ String ], required: false
      argument :authorize_params, GraphQL::Types::JSON, required: false
      argument :claims, GraphQL::Types::JSON, required: false
      argument :subject_claim, String, required: false
      argument :issuer, String, required: false
      argument :jwks_uri, String, required: false
      argument :token_auth_method, String, required: false
      argument :response_mode, String, required: false
      argument :team_id, String, required: false
      argument :key_id, String, required: false
      argument :private_key, String, required: false
      argument :role, String, required: false
      argument :trusts_email, Boolean, required: false
      argument :email_domains, [ String ], required: false
      argument :signup_scopes, [ String ], required: false

      field :provider, Types::ProviderType, null: false

      def resolve(key:, preset: nil, preset_values: nil, scopes: nil, email_domains: nil, signup_scopes: nil, **attributes)
        refuse!("a provider is already keyed #{key}") if ::Provider.exists?(key: key)

        provider = ::Provider.new(**preset_attributes(preset, preset_values), key: key)
        provider.assign_attributes(attributes.compact)
        provider.scopes = Scopes.join(scopes) if scopes
        provider.email_domains = ProviderDomains.join(email_domains) if email_domains
        provider.signup_scopes = Scopes.join(signup_scopes) if signup_scopes

        discover(provider)

        save!(provider)
        audit!(::Event::PROVIDER_CREATED, provider: provider.key, name: provider.name)

        { provider: provider }
      end

      private

        def preset_attributes(preset, values)
          return {} if preset.blank?

          found = ::ProviderPreset.find(preset) || refuse!("there is no preset named #{preset}")

          found.attributes(values.is_a?(Hash) ? values : {})
        rescue ::ProviderPreset::Unusable => e
          refuse!(e.message)
        end

        def discover(provider)
          return unless provider.oidc? && provider.issuer.present?
          return if provider.authorization_url.present? && provider.token_url.present?

          document = ::Provider.discover(provider.issuer)

          provider.authorization_url ||= document["authorization_endpoint"]
          provider.token_url ||= document["token_endpoint"]
          provider.userinfo_url ||= document["userinfo_endpoint"]
          provider.jwks_uri ||= document["jwks_uri"]
        rescue ::Provider::Untrusted, ::Provider::Refused, ::Provider::Unreachable => e
          refuse!(e.message)
        end
    end
  end
end
