module Manage
  module Mutations
    class RestoreProvider < BaseMutation
      argument :key, ID

      field :provider, Types::ProviderType, null: false

      def resolve(key:)
        provider = provider!(key)

        refuse!("#{provider.name} is not archived") unless provider.archived?

        provider.archived_at = nil
        save!(provider)

        audit!(::Event::PROVIDER_UPDATED, provider: provider.key, changed: [ "archived_at" ])

        { provider: provider }
      end
    end
  end
end
