module Manage
  module Mutations
    class ArchiveProvider < BaseMutation
      argument :key, ID

      field :provider, Types::ProviderType, null: false

      def resolve(key:)
        provider = provider!(key)

        refuse!("#{provider.name} is already archived") if provider.archived?

        provider.archived_at = Time.current
        save!(provider)

        audit!(::Event::PROVIDER_ARCHIVED, provider: provider.key, name: provider.name)

        { provider: provider }
      end
    end
  end
end
