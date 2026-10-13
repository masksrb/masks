module Masks
  module Server
    module Manage
      module Mutations
        class AddApp < BaseMutation
          requires :security

          argument :preset, ID
          argument :base_url, String, description: "Where the app is served, such as https://grafana.example.com."
          argument :name, String, required: false, description: "What people see."
          argument :slug, String, required: false,
                   description: "The name some apps put in their redirect URI, such as Gitea's authentication source."

          field :client, Types::ClientType, null: false
          field :secret, String
          field :settings, [ Types::AppSettingType ], null: false
          field :guide, String

          def resolve(preset:, base_url:, name: nil, slug: nil)
            found = Masks::Server::AppPreset.find(preset) || refuse!("no app preset called #{preset}")

            client = Masks::Server::Client.new(
              client_id: SecureRandom.uuid,
              name: name.presence || (found.forward? ? URI.parse(base_url.to_s).host : found.name),
              redirect_uris: found.redirect_uris(base: base_url, name: slug),
              allowed_scopes: Scopes.join(found.scopes),
              client_uri: base_url.to_s.strip.delete_suffix("/"),
              consent_required: false,
              dynamic: false,
              approved_at: Time.current,
              approved_by: viewer,
              **(found.forward? ? forwarded : redirected)
            )

            secret = client.issue_secret! unless found.forward?
            save!(client)

            audit!(Masks::Server::Event::CLIENT_CREATED, client: client, name: client.name, preset: found.key)

            {
              client: client, secret: secret, guide: found.guide,
              settings: found.settings(base: base_url, issuer: context[:issuer], client: client, secret: secret, name: slug)
            }
          rescue Masks::Server::AppPreset::Unusable, URI::InvalidURIError => e
            refuse!(e.message)
          end

          private

            def forwarded
              { protocol: Masks::Server::Client::FORWARD, grant_types: [], response_types: [],
                token_endpoint_auth_method: "none" }
            end

            def redirected
              { grant_types: %w[authorization_code refresh_token],
                response_types: Masks::Server::Client.response_types_for(%w[authorization_code]),
                token_endpoint_auth_method: Masks::Server::Client::DEFAULT_AUTH_METHOD }
            end
        end
      end
    end
  end
end
