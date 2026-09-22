module Masks
  module Server
    module Manage
      module Mutations
        class RegisterProvider < BaseMutation
          argument :key, ID

          field :provider, Types::ProviderType, null: false

          def resolve(key:)
            provider = provider!(key)

            refuse!("only an MCP server's authorization server is registered with") unless provider.mcp?

            provider.register!(callback: provider.callback_url)

            save!(provider)
            audit!(Masks::Server::Event::PROVIDER_UPDATED, provider: provider.key, changed: %w[client_id registered_at])

            { provider: provider }
          rescue Masks::Server::Provider::Untrusted, Masks::Server::Provider::Refused, Masks::Server::Provider::Unreachable => e
            refuse!(e.message)
          end
        end
      end
    end
  end
end
