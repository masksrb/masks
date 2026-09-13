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

        audit!(::Event::ADAPTER_TESTED, adapter: adapter.key, service: adapter.service, delivered: true)

        { delivered: true, failure: nil }
      rescue ::Adapter::Failed => failure
        audit!(::Event::ADAPTER_TESTED, adapter: adapter.key, service: adapter.service, delivered: false)

        { delivered: false, failure: failure.message }
      end
    end
  end
end
