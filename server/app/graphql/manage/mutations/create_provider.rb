module Manage
  module Mutations
    class CreateProvider < BaseMutation
      argument :key, ID
      argument :name, String
      argument :authorization_url, String
      argument :token_url, String
      argument :client_id, String
      argument :client_secret, String, required: false
      argument :revocation_url, String, required: false
      argument :userinfo_url, String, required: false
      argument :scopes, [ String ], required: false
      argument :authorize_params, GraphQL::Types::JSON, required: false
      argument :subject_claim, String, required: false
      argument :label_claim, String, required: false
      argument :issuer, String, required: false
      argument :jwks_uri, String, required: false
      argument :signs_in, Boolean, required: false
      argument :provisions, Boolean, required: false
      argument :email_domains, [ String ], required: false
      argument :signup_scopes, [ String ], required: false

      field :provider, Types::ProviderType, null: false

      def resolve(key:, scopes: nil, authorize_params: nil, email_domains: nil, signup_scopes: nil, **attributes)
        refuse!("a provider is already keyed #{key}") if ::Provider.exists?(key: key)

        provider = ::Provider.new(**attributes.compact, key: key)
        provider.scopes = Scopes.join(scopes) if scopes
        provider.authorize_params = authorize_params if authorize_params
        provider.email_domains = domains(email_domains) if email_domains
        provider.signup_scopes = Scopes.join(signup_scopes) if signup_scopes

        save!(provider)
        audit!(::Event::PROVIDER_CREATED, provider: provider.key, name: provider.name)

        { provider: provider }
      end

      private

        def domains(held)
          held.map { |one| one.to_s.strip.downcase.delete_prefix("@") }.reject(&:empty?).uniq.join(" ")
        end
    end
  end
end
