module Masks
  module Server
    module Manage
      module Mutations
        class TestAdapter < BaseMutation
          argument :key, ID
          argument :to, String

          field :delivered, Boolean, null: false
          field :failure, String

          def resolve(key:, to:)
            adapter = adapter!(key)

            adapter.deliver_test(to)

            audit!(Masks::Server::Event::ADAPTER_TESTED, adapter: adapter.key, service: adapter.service, delivered: true)

            { delivered: true, failure: nil }
          rescue Masks::Server::Adapter::Failed => failure
            audit!(Masks::Server::Event::ADAPTER_TESTED, adapter: adapter.key, service: adapter.service, delivered: false)

            { delivered: false, failure: failure.message }
          end
        end
      end
    end
  end
end
