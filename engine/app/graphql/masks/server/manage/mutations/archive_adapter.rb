module Masks
  module Server
    module Manage
      module Mutations
        class ArchiveAdapter < BaseMutation
          argument :key, ID

          field :adapter, Types::AdapterType, null: false

          def resolve(key:)
            adapter = adapter!(key)

            refuse!("#{adapter.name} is already archived") if adapter.archived?

            adapter.assign_attributes(archived_at: Time.current, primary: false)
            save!(adapter)

            audit!(Masks::Server::Event::ADAPTER_ARCHIVED, adapter: adapter.key, service: adapter.service)

            { adapter: adapter }
          end
        end
      end
    end
  end
end
