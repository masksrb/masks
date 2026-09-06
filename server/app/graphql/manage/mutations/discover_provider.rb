module Manage
  module Mutations
    class DiscoverProvider < BaseMutation
      argument :issuer, String

      field :issuer, String, null: false
      field :authorization_url, String, null: false
      field :token_url, String, null: false
      field :userinfo_url, String
      field :revocation_url, String
      field :jwks_uri, String, null: false
      field :scopes_supported, [ String ], null: false

      def resolve(issuer:)
        document = ::Provider.discover(issuer)

        missing = %w[authorization_endpoint token_endpoint jwks_uri].reject { |key| document[key].present? }

        refuse!("#{issuer} publishes no #{missing.join(', ')}") if missing.any?

        {
          issuer: document["issuer"].to_s.chomp("/"),
          authorization_url: document["authorization_endpoint"],
          token_url: document["token_endpoint"],
          userinfo_url: document["userinfo_endpoint"],
          revocation_url: document["revocation_endpoint"],
          jwks_uri: document["jwks_uri"],
          scopes_supported: Array(document["scopes_supported"])
        }
      rescue ::Provider::Untrusted, ::Provider::Refused, ::Provider::Unreachable => e
        refuse!(e.message)
      end
    end
  end
end
