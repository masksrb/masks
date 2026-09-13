module Manage
  module Mutations
    class CreateAdapter < BaseMutation
      argument :key, ID
      argument :service, String
      argument :name, String
      argument :config, GraphQL::Types::JSON, required: false
      argument :primary, Boolean, required: false

      field :adapter, Types::AdapterType, null: false

      def resolve(key:, service:, name:, config: nil, primary: nil)
        klass = ::Adapter.service_for(service) || refuse!("there is no adapter for #{service}")

        refuse!("an adapter is already keyed #{key}") if ::Adapter.exists?(key: key)

        adapter = klass.new(key: key, name: name)
        adapter.configure(config)
        adapter.primary = primary.nil? ? ::Adapter.primary(klass.kind).nil? : primary

        save!(adapter)

        audit!(::Event::ADAPTER_CREATED, adapter: adapter.key, service: adapter.service)

        { adapter: adapter }
      end
    end
  end
end
