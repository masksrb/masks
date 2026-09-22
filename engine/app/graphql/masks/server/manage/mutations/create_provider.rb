module Masks
  module Server
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
          argument :idp_entity_id, String, required: false
          argument :idp_sso_url, String, required: false
          argument :idp_certificates, String, required: false
          argument :metadata_url, String, required: false
          argument :name_id_format, String, required: false
          argument :role, String, required: false
          argument :trusts_email, Boolean, required: false
          argument :email_domains, [ String ], required: false
          argument :signup_scopes, [ String ], required: false
          argument :delegates, Boolean, required: false
          argument :delegated_scopes, [ String ], required: false
          argument :delegation_params, GraphQL::Types::JSON, required: false
          argument :resource_url, String, required: false

          field :provider, Types::ProviderType, null: false

          def resolve(key:, preset: nil, preset_values: nil, scopes: nil, email_domains: nil, signup_scopes: nil,
                      delegated_scopes: nil, **attributes)
            refuse!("a provider is already keyed #{key}") if Masks::Server::Provider.exists?(key: key)

            provider = Masks::Server::Provider.new(**preset_attributes(preset, preset_values), key: key)
            provider.assign_attributes(attributes.compact)
            provider.scopes = Scopes.join(scopes) if scopes
            provider.email_domains = ProviderDomains.join(email_domains) if email_domains
            provider.signup_scopes = Scopes.join(signup_scopes) if signup_scopes
            provider.delegated_scopes = Scopes.join(delegated_scopes) if delegated_scopes

            discover(provider)
            read_metadata(provider)
            register(provider)

            save!(provider)
            audit!(Masks::Server::Event::PROVIDER_CREATED, provider: provider.key, name: provider.name)

            { provider: provider }
          end

          private

            def preset_attributes(preset, values)
              return {} if preset.blank?

              found = Masks::Server::ProviderPreset.find(preset) || refuse!("there is no preset named #{preset}")

              found.attributes(values.is_a?(Hash) ? values : {})
            rescue Masks::Server::ProviderPreset::Unusable => e
              refuse!(e.message)
            end

            def register(provider)
              return unless provider.mcp? && provider.client_id.blank?

              refuse!("an MCP server needs its URL") if provider.resource_url.blank?

              provider.register!(callback: provider.callback_url)
            rescue Masks::Server::Provider::Untrusted, Masks::Server::Provider::Refused, Masks::Server::Provider::Unreachable => e
              refuse!(e.message)
            end

            def read_metadata(provider)
              return unless provider.saml? && provider.metadata_url.present? && provider.idp_sso_url.blank?

              provider.assign_attributes(Masks::Server::Federation::Saml.parse_metadata(provider.fetch_text(provider.metadata_url, Masks::Server::Federation::Saml::METADATA_LIMIT)))
              provider.metadata_fetched_at = Time.current
            rescue Masks::Server::Provider::Untrusted, Masks::Server::Provider::Refused, Masks::Server::Provider::Unreachable => e
              refuse!(e.message)
            end

            def discover(provider)
              return unless provider.oidc? && provider.issuer.present?
              return if provider.authorization_url.present? && provider.token_url.present?

              document = Masks::Server::Provider.discover(provider.issuer)

              provider.authorization_url ||= document["authorization_endpoint"]
              provider.token_url ||= document["token_endpoint"]
              provider.userinfo_url ||= document["userinfo_endpoint"]
              provider.jwks_uri ||= document["jwks_uri"]
            rescue Masks::Server::Provider::Untrusted, Masks::Server::Provider::Refused, Masks::Server::Provider::Unreachable => e
              refuse!(e.message)
            end
        end
      end
    end
  end
end
