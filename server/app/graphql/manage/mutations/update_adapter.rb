module Manage
  module Mutations
    class UpdateAdapter < BaseMutation
      argument :key, ID
      argument :name, String, required: false
      argument :config, GraphQL::Types::JSON, required: false
      argument :primary, Boolean, required: false

      field :adapter, Types::AdapterType, null: false

      def resolve(key:, name: nil, config: nil, primary: nil)
        adapter = adapter!(key)

        refuse!("#{adapter.name} is archived; restore it first") if adapter.archived?

        adapter.name = name unless name.nil?
        adapter.configure(config) unless config.nil?
        adapter.primary = primary unless primary.nil?

        save!(adapter)

        audit!(::Event::ADAPTER_UPDATED, adapter: adapter.key, service: adapter.service,
                                         changed: Array(config&.keys) + [ name && "name", primary.nil? ? nil : "primary" ].compact)

        { adapter: adapter }
      end
    end
  end
end
