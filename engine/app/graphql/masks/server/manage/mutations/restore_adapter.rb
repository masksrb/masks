module Masks
  module Server
    module Manage
      module Mutations
        class RestoreAdapter < BaseMutation
          argument :key, ID

          field :adapter, Types::AdapterType, null: false

          def resolve(key:)
            adapter = adapter!(key)

            refuse!("#{adapter.name} is not archived") unless adapter.archived?

            adapter.archived_at = nil
            save!(adapter)

            audit!(Masks::Server::Event::ADAPTER_UPDATED, adapter: adapter.key, service: adapter.service, changed: [ "restored" ])

            { adapter: adapter }
          end
        end
      end
    end
  end
end
